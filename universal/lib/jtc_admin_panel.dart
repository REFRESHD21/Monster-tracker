import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _jtcUrl = 'https://jmuxmgsbmnyqmetakhua.supabase.co';
const _jtcKey = 'sb_publishable_9tqPZDnWGBjvFOqtuKQmYQ_kXjMfeUa';
bool _jtcInitialized = false;

class _JtcSecureAuthStorage extends LocalStorage {
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  @override Future<void> initialize() async {}
  @override Future<String?> accessToken() => storage.read(key: supabasePersistSessionKey);
  @override Future<bool> hasAccessToken() => storage.containsKey(key: supabasePersistSessionKey);
  @override Future<void> persistSession(String persistSessionString) => storage.write(key: supabasePersistSessionKey, value: persistSessionString);
  @override Future<void> removePersistedSession() => storage.delete(key: supabasePersistSessionKey);
}

class JtcAdminPanel extends StatefulWidget {
  const JtcAdminPanel({super.key});
  @override State<JtcAdminPanel> createState() => _JtcAdminPanelState();
}

class _JtcAdminPanelState extends State<JtcAdminPanel> {
  SupabaseClient? db;
  bool loading = true, working = false, admin = false;
  String? error;
  int section = 0;
  List<Map<String,dynamic>> products = [], reservations = [], messages = [];
  final email = TextEditingController(), password = TextEditingController();

  @override void initState() { super.initState(); connect(); }
  @override void dispose() { email.dispose(); password.dispose(); super.dispose(); }

  Future<void> connect() async {
    try {
      if (!_jtcInitialized) {
        await Supabase.initialize(url: _jtcUrl, publishableKey: _jtcKey, authOptions: FlutterAuthClientOptions(localStorage: _JtcSecureAuthStorage()));
        _jtcInitialized = true;
      }
      db = Supabase.instance.client;
      if (db!.auth.currentUser == null) { if (mounted) setState(() => loading = false); return; }
      await verifyAdmin();
    } catch (e) { if (mounted) setState(() { error = 'Connection failed. Check internet and Supabase configuration.'; loading = false; }); }
  }

  Future<void> verifyAdmin() async {
    if (db == null) return;
    setState(() { loading = true; error = null; });
    try {
      final user = db!.auth.currentUser;
      if (user == null) { setState(() { admin = false; loading = false; }); return; }
      final rows = await db!.from('admin_users').select('user_id').eq('user_id', user.id);
      if (rows.isEmpty) {
        await db!.auth.signOut();
        setState(() { admin = false; loading = false; error = 'This account has not been authorised as an administrator.'; });
        return;
      }
      setState(() => admin = true);
      await loadData();
    } catch (_) { if (mounted) setState(() { error = 'Could not verify admin access or load data. Check your account and permissions.'; loading = false; }); }
  }

  Future<void> signIn() async {
    if (db == null) return;
    setState(() { working = true; error = null; });
    try { await db!.auth.signInWithPassword(email: email.text.trim(), password: password.text); await verifyAdmin(); }
    on AuthException catch (e) { if (mounted) setState(() => error = e.message); }
    catch (_) { if (mounted) setState(() => error = 'Sign-in failed. Check the details and try again.'); }
    finally { if (mounted) setState(() => working = false); }
  }

  Future<void> loadData() async {
    if (db == null) return;
    try {
      final r = await Future.wait([
        db!.from('products').select().order('name'),
        db!.from('reservations').select().order('requested_at', ascending: false).limit(200),
        db!.from('contact_messages').select().order('created_at', ascending: false).limit(100),
      ]);
      if (mounted) setState(() { products = List<Map<String,dynamic>>.from(r[0]); reservations = List<Map<String,dynamic>>.from(r[1]); messages = List<Map<String,dynamic>>.from(r[2]); loading = false; error = null; });
    } catch (_) { if (mounted) setState(() { loading = false; error = 'Could not load admin data. Verify Supabase permissions.'; }); }
  }

  Future<void> runAction(Future<void> Function() action, String success) async {
    setState(() { working = true; error = null; });
    try { await action(); await loadData(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success))); }
    catch (e) { if (mounted) setState(() => error = 'Action failed: ' + e.toString()); }
    finally { if (mounted) setState(() => working = false); }
  }

  Future<void> editProduct([Map<String,dynamic>? p]) async {
    final name = TextEditingController(text: p?['name']?.toString() ?? '');
    final desc = TextEditingController(text: p?['description']?.toString() ?? '');
    final price = TextEditingController(text: p?['price']?.toString() ?? '');
    final stock = TextEditingController(text: p?['stock_on_hand']?.toString() ?? '0');
    final image = TextEditingController(text: p?['image_url']?.toString() ?? '');
    final offer = TextEditingController(text: p?['bundle_offer']?.toString() ?? '');
    bool published = p?['is_published'] == true;
    final key = GlobalKey<FormState>();
    final ok = await showDialog<bool>(context: context, builder: (d) => StatefulBuilder(builder: (d, refresh) => AlertDialog(
      title: Text(p == null ? 'Add website product' : 'Edit website product'),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: Form(key: key, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Product name'), validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null),
        TextFormField(controller: desc, decoration: const InputDecoration(labelText: 'Description'), maxLines: 2),
        TextFormField(controller: price, decoration: const InputDecoration(labelText: 'Price (AUD)'), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: (v) { final n = double.tryParse(v ?? ''); return n == null || n < 0 ? 'Enter a valid price' : null; }),
        TextFormField(controller: stock, decoration: const InputDecoration(labelText: 'Stock on hand'), keyboardType: TextInputType.number, validator: (v) { final n = int.tryParse(v ?? ''); return n == null || n < 0 ? 'Enter a whole number ≥ 0' : null; }),
        TextFormField(controller: image, decoration: const InputDecoration(labelText: 'Image URL (optional)')),
        TextFormField(controller: offer, decoration: const InputDecoration(labelText: 'Bundle offer (optional)')),
        SwitchListTile(value: published, onChanged: (v) => refresh(() => published = v), title: const Text('Publish on website'), contentPadding: EdgeInsets.zero),
      ])))),
      actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), FilledButton(onPressed: () { if (key.currentState!.validate()) Navigator.pop(d, true); }, child: const Text('Save'))],
    ));
    if (ok == true) {
      final data = <String,dynamic>{'name':name.text.trim(),'description':desc.text.trim(),'price':double.parse(price.text),'stock_on_hand':int.parse(stock.text),'image_url':image.text.trim().isEmpty ? null : image.text.trim(),'bundle_offer':offer.text.trim().isEmpty ? null : offer.text.trim(),'is_published':published,'updated_at':DateTime.now().toUtc().toIso8601String()};
      await runAction(() async { if (p == null) { await db!.from('products').insert(data); } else { await db!.from('products').update(data).eq('id', p['id']); } }, 'Product saved.');
    }
    name.dispose(); desc.dispose(); price.dispose(); stock.dispose(); image.dispose(); offer.dispose();
  }

  Future<void> reservationAction(Map<String,dynamic> r, bool approve) async {
    final note = TextEditingController();
    final yes = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: Text(approve ? 'Approve reservation?' : 'Reject reservation?'), content: TextField(controller: note, maxLines: 2, decoration: const InputDecoration(labelText: 'Admin note (optional)')), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(approve ? 'Approve' : 'Reject'))]));
    if (yes == true) await runAction(() async { await db!.rpc(approve ? 'approve_reservation' : 'reject_reservation', params: {'p_reservation_id':r['id'],'p_admin_note':note.text.trim().isEmpty ? null : note.text.trim()}); }, approve ? 'Approved; stock was rechecked.' : 'Reservation rejected.');
    note.dispose();
  }

  String cash(dynamic n) => '\$' + (double.tryParse(n?.toString() ?? '') ?? 0).toStringAsFixed(2);
  @override Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (!admin) return signInView();
    final pending = reservations.where((r) => r['status'] == 'pending').length;
    return RefreshIndicator(onRefresh: loadData, child: ListView(padding: const EdgeInsets.all(16), children: [
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Expanded(child: Text('JTC Drinks Admin', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))), IconButton(onPressed: loadData, icon: const Icon(Icons.refresh), tooltip: 'Refresh'), IconButton(onPressed: () async { await db!.auth.signOut(); if (mounted) setState(() => admin = false); }, icon: const Icon(Icons.logout), tooltip: 'Sign out')]),
        const Text('Connected to the live website database.'),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          metric('Products', products.length.toString(), Icons.inventory_2),
          metric('Published', products.where((p) => p['is_published'] == true).length.toString(), Icons.public),
          metric('Pending', pending.toString(), Icons.pending_actions),
        ]),
      ]))),
      if (error != null) Card(color: Theme.of(context).colorScheme.errorContainer, child: Padding(padding: const EdgeInsets.all(12), child: Text(error!))),
      SegmentedButton<int>(segments: const [ButtonSegment(value:0,label:Text('Products'),icon:Icon(Icons.inventory_2)),ButtonSegment(value:1,label:Text('Reservations'),icon:Icon(Icons.event_note)),ButtonSegment(value:2,label:Text('Messages'),icon:Icon(Icons.mail_outline))], selected: {section}, onSelectionChanged: (v) => setState(() => section = v.first)),
      const SizedBox(height: 10),
      if (section == 0) ...[
        Align(alignment: Alignment.centerRight, child: FilledButton.icon(onPressed: working ? null : () => editProduct(), icon: const Icon(Icons.add), label: const Text('Add product'))),
        if (products.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No website products yet. Add the first one above.')),
        ...products.map((p) => Card(child: ListTile(leading: const CircleAvatar(child: Icon(Icons.local_drink)), title: Text(p['name'].toString()), subtitle: Text(cash(p['price']) + ' · Stock ' + p['stock_on_hand'].toString() + ' · ' + (p['is_published'] == true ? 'Published' : 'Hidden')), trailing: IconButton(onPressed: working ? null : () => editProduct(p), icon: const Icon(Icons.edit_outlined), tooltip: 'Edit product')))),
      ] else if (section == 1) ...[
        if (reservations.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No reservation requests yet.')),
        ...reservations.map((r) => Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text(r['customer_name'].toString() + ' · Qty ' + r['quantity'].toString(), style: const TextStyle(fontWeight: FontWeight.bold))), Chip(label: Text(r['status'].toString().toUpperCase()))]),
          Text(r['customer_email'].toString()),
          if ((r['note'] ?? '').toString().isNotEmpty) Text('Note: ' + r['note'].toString()),
          if ((r['admin_note'] ?? '').toString().isNotEmpty) Text('Admin note: ' + r['admin_note'].toString()),
          if (r['status'] == 'pending') Wrap(children: [TextButton.icon(onPressed: working ? null : () => reservationAction(r, true), icon: const Icon(Icons.check), label: const Text('Approve')), TextButton.icon(onPressed: working ? null : () => reservationAction(r, false), icon: const Icon(Icons.close), label: const Text('Reject'))]),
          if (r['status'] == 'approved') Text('Expires: ' + (r['expires_at'] ?? 'not set').toString()),
        ])))),
      ] else ...[
        if (messages.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No customer messages yet.')),
        ...messages.map((m) => Card(child: ListTile(title: Text(m['name'].toString()), subtitle: Text(m['email'].toString() + '\n' + m['message'].toString() + '\nReceived: ' + m['created_at'].toString()), isThreeLine: true, leading: const Icon(Icons.mail_outline)))),
      ],
      if (working) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
    ]));
  }

  Widget metric(String label, String value, IconData icon) => SizedBox(width: 105, child: Card(color: Theme.of(context).colorScheme.surfaceContainerHighest, child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon), const SizedBox(height: 8), Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), Text(label)]))));
  Widget signInView() => Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Card(child: Padding(padding: const EdgeInsets.all(22), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    const Icon(Icons.admin_panel_settings_outlined, size: 48), const SizedBox(height: 12), const Text('JTC Drinks Admin', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)), const SizedBox(height: 8), const Text('Sign in with your authorised owner account.', textAlign: TextAlign.center),
    const SizedBox(height: 20), TextField(controller: email, keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email], decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined))),
    const SizedBox(height: 12), TextField(controller: password, obscureText: true, autofillHints: const [AutofillHints.password], decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_outline)), onSubmitted: (_) => signIn()),
    if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
    const SizedBox(height: 16), FilledButton(onPressed: working ? null : signIn, child: working ? const CircularProgressIndicator() : const Text('Sign in')),
    TextButton(onPressed: connect, child: const Text('Retry connection')),
  ]))))));
}
