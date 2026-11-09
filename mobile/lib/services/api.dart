import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

typedef Json = Map<String, dynamic>;

/// Thin wrapper over Supabase so screens stay testable (tests subclass this).
class Api {
  Api([this._db]);
  final SupabaseClient? _db;
  SupabaseClient get db => _db ?? Supabase.instance.client;

  // ---------- auth ----------
  User? get user => db.auth.currentUser;
  bool get isGuest => user == null || user!.isAnonymous;
  Stream<AuthState> get authChanges => db.auth.onAuthStateChange;

  /// First open: anonymous sign-in, then record_install once with the APK referrer.
  Future<void> ensureSession(SharedPreferences prefs) async {
    if (db.auth.currentSession == null) await db.auth.signInAnonymously();
    if (prefs.getBool('install_recorded') == true) return;
    final rnd = Random.secure();
    String token(int n) => List.generate(n, (_) => rnd.nextInt(16).toRadixString(16)).join();
    final id = prefs.getString('install_id') ?? token(32);
    final secret = prefs.getString('install_secret') ?? token(48);
    await prefs.setString('install_id', id);
    await prefs.setString('install_secret', secret);
    await db.rpc('record_install', params: {
      'p_install_id': id,
      'p_referrer_status': Config.apkReferrer.isEmpty ? 'none' : 'apk_define',
      'p_raw_referrer': Config.apkReferrer,
      'p_install_secret': secret,
    });
    await prefs.setBool('install_recorded', true);
  }

  /// Guest → account: keeps the same user id (all guest data stays).
  Future<void> signUp(String email, String password) async {
    if (user != null && user!.isAnonymous) {
      await db.auth.updateUser(UserAttributes(email: email, password: password), emailRedirectTo: Config.authCallback);
    } else {
      await db.auth.signUp(email: email, password: password, emailRedirectTo: Config.authCallback);
    }
  }

  Future<void> signIn(String email, String password) => db.auth.signInWithPassword(email: email, password: password);
  Future<void> resetPassword(String email) => db.auth.resetPasswordForEmail(email, redirectTo: Config.authCallback);
  Future<void> setPassword(String password) => db.auth.updateUser(UserAttributes(password: password));

  Future<void> signOut() async {
    await db.auth.signOut();
    await db.auth.signInAnonymously();
  }

  Future<void> deleteAccount() async {
    await db.functions.invoke('delete-account');
    await db.auth.signOut();
    await db.auth.signInAnonymously();
  }

  Future<bool> hasConsent() async =>
      (await db.from('consents').select('policy_version').eq('user_id', user!.id).limit(1)).isNotEmpty;
  Future<void> giveConsent() =>
      db.from('consents').upsert({'user_id': user!.id, 'policy_version': Config.policyVersion});

  // ---------- status ----------
  Future<Json> myStatus() async => Json.from(await db.rpc('my_status') as Map);
  Future<Json> planOffers() async => Json.from(await db.rpc('plan_offers') as Map);
  Future<List<Json>> activePlans() async =>
      List<Json>.from(await db.from('plans').select('id,name,price_inr,duration_days').eq('active', true).order('position'));
  Future<String> requestFullAccess() async => (await db.rpc('request_full_access')).toString();

  /// Realtime: app_mode / plan_catalog changes → callback.
  RealtimeChannel subscribeMode(void Function() onChange) => db
      .channel('mode')
      .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'app_mode', callback: (_) => onChange())
      .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'plan_catalog', callback: (_) => onChange())
      .subscribe();
  Future<void> unsubscribe(RealtimeChannel c) => db.removeChannel(c);

  // ---------- payments ----------
  Future<Json> createOrder(String planId) async => Json.from(await db.rpc('create_order', params: {'p_plan_id': planId}) as Map);
  Future<String> reportResult(String orderId, String raw) async {
    final r = Json.from(await db.rpc('report_result', params: {'p_order_id': orderId, 'p_raw': raw}) as Map);
    return r['status'] as String;
  }

  Future<Json?> orderStatus(String orderId) async {
    final r = await db.rpc('order_status', params: {'p_order_id': orderId});
    return r == null ? null : Json.from(r as Map);
  }

  Future<Json> claimFreePlan(String planId) async =>
      Json.from(await db.rpc('claim_free_plan', params: {'p_plan_id': planId}) as Map);
  Future<List<Json>> paymentHistory() async => List<Json>.from(await db
      .from('payment_orders')
      .select('id,reference,amount_paise,status,created_at,plans(name)')
      .order('created_at', ascending: false)
      .limit(100));
  Future<Json?> latestPendingOrder() async {
    final r = await db.from('payment_orders').select('id,reference,status').inFilter('status', ['pending', 'submitted', 'review'])
        .order('created_at', ascending: false).limit(1);
    return r.isEmpty ? null : Json.from(r.first);
  }

  // ---------- content ----------
  static const pageSize = 20;
  Future<List<Json>> latestPosts({int page = 0, String? category, String? query}) async {
    var q = db.from('posts').select('id,title,description,created_at,channel_id,channels!inner(id,name,category,icon_url),post_items(thumbnail_key,is_premium)');
    if (category != null) q = q.eq('channels.category', category);
    if (query != null && query.isNotEmpty) q = q.ilike('title', '%$query%');
    final blocked = await blockedChannelIds();
    if (blocked.isNotEmpty) q = q.not('channel_id', 'in', '(${blocked.join(',')})');
    return List<Json>.from(await q.order('created_at', ascending: false).range(page * pageSize, page * pageSize + pageSize - 1));
  }

  Future<List<String>> categories() async {
    final r = await db.from('channels').select('category').not('category', 'is', null).limit(200);
    return {for (final c in r) c['category'] as String}.toList()..sort();
  }

  Future<List<String>> blockedChannelIds() async {
    if (user == null) return const [];
    final r = await db.from('blocked_channels').select('channel_id').eq('user_id', user!.id);
    return [for (final x in r) x['channel_id'] as String];
  }

  /// tab: discover | joined | mine
  Future<List<Json>> channels(String tab) async {
    if (tab == 'mine') {
      return List<Json>.from(await db.from('channels').select().eq('created_by', user!.id).order('created_at', ascending: false));
    }
    if (tab == 'joined') {
      final r = await db.from('channel_members').select('channels(*)').eq('user_id', user!.id);
      return [for (final x in r) if (x['channels'] != null) Json.from(x['channels'] as Map)];
    }
    return List<Json>.from(await db.from('channels').select().eq('review_status', 'approved').order('members_count', ascending: false).limit(100));
  }

  Future<Json?> channel(String id) async => await db.from('channels').select().eq('id', id).maybeSingle();
  Future<bool> isMember(String channelId) async =>
      (await db.from('channel_members').select('channel_id').eq('channel_id', channelId).eq('user_id', user!.id)).isNotEmpty;
  Future<void> join(String channelId) => db.from('channel_members').insert({'channel_id': channelId, 'user_id': user!.id});
  Future<void> leave(String channelId) => db.from('channel_members').delete().eq('channel_id', channelId).eq('user_id', user!.id);
  Future<List<Json>> channelPosts(String channelId) async => List<Json>.from(await db
      .from('posts')
      .select('id,title,description,created_at,status,post_items(thumbnail_key,is_premium)')
      .eq('channel_id', channelId)
      .order('created_at', ascending: false)
      .limit(100));
  Future<Json> saveChannel(Json row, {String? id}) async => id == null
      ? Json.from(await db.from('channels').insert(row).select().single())
      : Json.from(await db.from('channels').update(row).eq('id', id).select().single());

  Future<String> uploadIcon(String path, List<int> bytes) async {
    final key = '${user!.id}/${DateTime.now().millisecondsSinceEpoch}-${path.split('/').last}';
    await db.storage.from('channel-icons').uploadBinary(key, Uint8ListX.from(bytes));
    return key;
  }

  final _signed = <String, (String, DateTime)>{};

  /// Signed URL cache with refresh 5 min before expiry.
  Future<String?> signedUrl(String bucket, String? key, {int seconds = 3600, bool download = false}) async {
    if (key == null) return null;
    final ck = '$bucket/$key/$download';
    final hit = _signed[ck];
    if (hit != null && hit.$2.isAfter(DateTime.now().add(const Duration(minutes: 5)))) return hit.$1;
    try {
      final url = await db.storage.from(bucket).createSignedUrl(key, seconds, transform: null);
      final u = download ? '$url&download=' : url;
      _signed[ck] = (u, DateTime.now().add(Duration(seconds: seconds)));
      return u;
    } catch (_) {
      return null;
    }
  }

  void forgetSigned(String bucket, String key) => _signed.removeWhere((k, _) => k.startsWith('$bucket/$key/'));

  Future<Json?> post(String id) async =>
      await db.from('posts').select('*, channels(id,name,icon_url,created_by), post_items(*)').eq('id', id).maybeSingle();

  /// {key, kind: full|trailer|locked} from the server.
  Future<Json?> playable(String itemId) async {
    final r = await db.rpc('playable_key', params: {'p_item_id': itemId});
    return r == null ? null : Json.from(r as Map);
  }

  Future<void> report(String type, String id, String reason, String? details) => db.rpc('report_content',
      params: {'p_target_type': type, 'p_target_id': id, 'p_reason': reason, 'p_details': details});
  Future<void> blockChannel(String channelId) =>
      db.from('blocked_channels').upsert({'user_id': user!.id, 'channel_id': channelId});

  /// Creator upload: file → `media/<channel>/...`, then post + item.
  Future<void> uploadPost({required String channelId, required String title, String? description,
      required String fileName, required List<int> bytes, String? mime}) async {
    final ext = fileName.contains('.') ? fileName.split('.').last : 'bin';
    final key = '$channelId/${DateTime.now().microsecondsSinceEpoch}.$ext';
    await db.storage.from('media').uploadBinary(key, Uint8ListX.from(bytes), fileOptions: FileOptions(contentType: mime));
    final post = await db.from('posts').insert({'channel_id': channelId, 'title': title, 'description': description, 'status': 'published'}).select('id').single();
    await db.from('post_items').insert({'post_id': post['id'], 'media_key': key, 'thumbnail_key': (mime ?? '').startsWith('image/') ? key : null,
      'mime': mime, 'size_bytes': bytes.length});
  }

  // ---------- cloud ----------
  Future<List<Json>> cloudFolders(String? parentId) async {
    var q = db.from('cloud_folders').select();
    q = parentId == null ? q.isFilter('parent_id', null) : q.eq('parent_id', parentId);
    return List<Json>.from(await q.order('name'));
  }

  Future<List<Json>> allFolders() async => List<Json>.from(await db.from('cloud_folders').select('id,name').order('name'));

  Future<List<Json>> cloudFiles(String? folderId) async {
    var q = db.from('cloud_files').select();
    q = folderId == null ? q.isFilter('folder_id', null) : q.eq('folder_id', folderId);
    return List<Json>.from(await q.order('created_at', ascending: false));
  }

  Future<void> createFolder(String name, String? parentId) =>
      db.from('cloud_folders').insert({'name': name, 'parent_id': parentId, 'user_id': user!.id});
  Future<void> deleteFolder(String id) => db.from('cloud_folders').delete().eq('id', id);
  Future<void> renameFile(String id, String name) => db.from('cloud_files').update({'name': name}).eq('id', id);
  Future<void> moveFile(String id, String? folderId) => db.from('cloud_files').update({'folder_id': folderId}).eq('id', id);
  Future<void> deleteFile(String id) => db.functions.invoke('cloud-files', body: {'action': 'delete', 'id': id});
  Future<String?> fileUrl(String id) async =>
      (await db.functions.invoke('cloud-files', body: {'action': 'download', 'id': id})).data?['url'] as String?;

  /// Upload with progress. Retries the transfer up to 3 times on network errors.
  /// shortcut: re-sends the whole file on retry (no TUS chunk resume); switch to resumable uploads for >500 MB files.
  Future<void> uploadCloud({required String name, required int size, String? mime, String? folderId,
      required Stream<List<int>> Function() open, required void Function(double) onProgress}) async {
    final res = await db.functions.invoke('cloud-files', body: {'action': 'upload', 'name': name, 'size': size, 'mime': mime, 'folder_id': folderId});
    final data = Json.from(res.data as Map);
    if (data['error'] != null) throw Exception(data['error']);
    final url = Uri.parse(data['upload_url'] as String);
    for (var attempt = 1;; attempt++) {
      try {
        final req = http.StreamedRequest('PUT', url)
          ..headers['Content-Type'] = mime ?? 'application/octet-stream'
          ..contentLength = size;
        var sent = 0;
        final done = req.send();
        await for (final chunk in open()) {
          req.sink.add(chunk);
          sent += chunk.length;
          onProgress(size == 0 ? 1 : sent / size);
        }
        unawaited(req.sink.close());
        final r = await done;
        if (r.statusCode >= 300) throw http.ClientException('upload failed ${r.statusCode}: ${await r.stream.bytesToString()}');
        return;
      } on http.ClientException {
        if (attempt >= 3) {
          await deleteFile(Json.from(data['file'] as Map)['id'] as String);
          rethrow;
        }
        await Future<void>.delayed(Duration(seconds: attempt * 2));
      }
    }
  }

  // ---------- play ----------
  Future<String> playChallenge() async => (await db.rpc('play_integrity_challenge')).toString();
  Future<bool> playVerify(String token, String nonce) async =>
      jsonDecode(jsonEncode((await db.functions.invoke('play-verify', body: {'token': token, 'nonce': nonce})).data))['verified'] == true;
}

extension Uint8ListX on List<int> {
  static Uint8List from(List<int> b) => b is Uint8List ? b : Uint8List.fromList(b);
}
