import 'package:flutter/material.dart';

import 'spike/fixture_library.dart';
import 'spike/reader_page.dart';
import 'spike/spike_log.dart';
import 'spike/spike_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final library = await FixtureLibrary.prepare();
  final store = await SpikeStore.open(library.root);
  runApp(SpikeApp(library: library, store: store));
}

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key, required this.library, required this.store});

  final FixtureLibrary library;
  final SpikeStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Reader engine spike',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF303943)),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF303943),
        brightness: Brightness.dark,
      ),
      home: FixtureListPage(library: library, store: store),
    );
  }
}

class FixtureListPage extends StatelessWidget {
  const FixtureListPage({
    super.key,
    required this.library,
    required this.store,
  });

  final FixtureLibrary library;
  final SpikeStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reader engine spike'),
        actions: [
          IconButton(
            tooltip: 'Event log',
            icon: const Icon(Icons.receipt_long),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const EventLogPage()),
            ),
          ),
        ],
      ),
      body: ListView(
        children: [
          for (final fixture in fixtures)
            ListTile(
              title: Text(fixture.label),
              subtitle: Text(
                store.position(fixture.id) == null
                    ? 'No saved position'
                    : 'Saved position available',
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ReaderPage(
                    fixture: fixture,
                    library: library,
                    store: store,
                  ),
                ),
              ),
              onLongPress: () async {
                await store.clear(fixture.id);
                SpikeLog.instance.add('[${fixture.id}] stored state cleared');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Cleared ${fixture.label}')),
                  );
                }
              },
            ),
        ],
      ),
    );
  }
}

class EventLogPage extends StatelessWidget {
  const EventLogPage({super.key});

  @override
  Widget build(BuildContext context) {
    final log = SpikeLog.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Event log')),
      body: ListenableBuilder(
        listenable: log,
        builder: (context, _) => ListView.builder(
          itemCount: log.entries.length,
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              log.entries[index],
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }
}
