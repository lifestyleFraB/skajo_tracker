import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert'; // Wichtig für das Speichern der Spieler-Liste

void main() {
  runApp(const SkajoApp());
}

class SkajoApp extends StatelessWidget {
  const SkajoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Skajo Ewige Kasse',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          primary: Colors.teal[700],
          secondary: Colors.amber[600],
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.grey[100],
      ),
      home: const SkajoBlockDashboard(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class Player {
  String name;
  double totalWallet; // Das angesammelte Geld aus ALLEN vorherigen Spielen

  Player({required this.name, this.totalWallet = 0.0});

  // Für das Speichern in den SharedPreferences
  Map<String, dynamic> toJson() => {'name': name, 'totalWallet': totalWallet};

  factory Player.fromJson(Map<String, dynamic> json) => Player(
    name: json['name'],
    totalWallet: (json['totalWallet'] as num).toDouble(),
  );
}

class SkajoBlockDashboard extends StatefulWidget {
  const SkajoBlockDashboard({super.key});

  @override
  State<SkajoBlockDashboard> createState() => _SkajoBlockDashboardState();
}

class _SkajoBlockDashboardState extends State<SkajoBlockDashboard> {
  final List<Player> _players = [];

  // Feste Matrix für 10 Runden und bis zu 5 Spieler (null = noch nicht gespielt)
  final List<List<int?>> _fixedRounds = List.generate(
    10,
    (_) => List.generate(5, (_) => null),
  );

  final TextEditingController _nameController = TextEditingController();
  final List<TextEditingController> _scoreControllers = List.generate(
    5,
    (_) => TextEditingController(),
  );

  @override
  void initState() {
    super.initState();
    _loadData(); // Lädt die Ewige Kasse beim Starten der App
  }

  // --- NEU: Laden & Speichern über SharedPreferences ---
  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? playersString = prefs.getString('skajo_players');

    if (playersString != null) {
      final List<dynamic> decoded = jsonDecode(playersString);
      setState(() {
        _players.clear();
        _players.addAll(decoded.map((item) => Player.fromJson(item)).toList());

        // Runden-Matrix für die geladenen Spieler initialisieren
        for (int i = 0; i < 10; i++) {
          for (int j = 0; j < 5; j++) {
            _fixedRounds[i][j] = j < _players.length ? 0 : null;
          }
        }
      });
    }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(_players.map((p) => p.toJson()).toList());
    await prefs.setString('skajo_players', encoded);
  }

  // Prüft, ob irgendein Spieler die 100 Punkte erreicht/überschritten hat
  bool get _isGameOver {
    if (_players.isEmpty) return false;
    for (int i = 0; i < _players.length; i++) {
      if (_getPlayerTotalScore(i) >= 100) {
        return true;
      }
    }
    return false;
  }

  int get _currentDealerIndex {
    if (_players.isEmpty) return 0;

    int nextRoundIndex = 0;
    for (int i = 0; i < 10; i++) {
      if (_fixedRounds[i][0] == null) {
        nextRoundIndex = i;
        break;
      }
    }
    return nextRoundIndex % _players.length;
  }

  void _addPlayer() {
    if (_players.length >= 5) {
      _showSnackBar('Maximale Spieleranzahl (5) erreicht!');
      return;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showSnackBar('Bitte einen Namen eingeben.');
      return;
    }
    if (_players.any((p) => p.name.toLowerCase() == name.toLowerCase())) {
      _showSnackBar('Spieler existiert bereits!');
      return;
    }

    setState(() {
      _players.add(Player(name: name));
      _nameController.clear();

      int playerIndex = _players.length - 1;
      for (int i = 0; i < 10; i++) {
        _fixedRounds[i][playerIndex] = 0;
      }
    });
    _saveData(); // Speichern nach Spieler-Hinzufügen
    Navigator.of(context).pop();
  }

  void _saveRoundScores(int roundIndex) {
    setState(() {
      for (int i = 0; i < _players.length; i++) {
        final text = _scoreControllers[i].text.trim();
        _fixedRounds[roundIndex][i] = int.tryParse(text) ?? 0;
      }
    });
    Navigator.of(context).pop();
  }

  int _getPlayerTotalScore(int playerIndex) {
    int total = 0;
    for (int i = 0; i < 10; i++) {
      total += (_fixedRounds[i][playerIndex] ?? 0);
    }
    return total;
  }

  // Korrigierte Geld-Berechnung: Höchste Punktzahl verliert!
  double _getPlayerCurrentGameMoney(int playerIndex) {
    if (_players.length < 2) return 0.0;

    bool gameStarted = false;
    for (int i = 0; i < 10; i++) {
      if (_fixedRounds[i][0] != null) {
        gameStarted = true;
        break;
      }
    }
    if (!gameStarted) return 0.0;

    List<MapEntry<int, int>> totalScores = [];
    for (int i = 0; i < _players.length; i++) {
      totalScores.add(MapEntry(i, _getPlayerTotalScore(i)));
    }

    // Sortieren nach Gesamtpunkten ABSTEIGEND (Höchste Punktzahl zuerst = Letzter Platz!)
    totalScores.sort((a, b) => b.value.compareTo(a.value));

    int highestTotalScore = totalScores.first.value;

    int? secondHighestTotalScore;
    for (var entry in totalScores) {
      if (entry.value < highestTotalScore) {
        secondHighestTotalScore = entry.value;
        break;
      }
    }

    int myTotalScore = _getPlayerTotalScore(playerIndex);

    if (myTotalScore == highestTotalScore) {
      return 1.00; // Meiste Punkte zahlen 1,00 €
    } else if (secondHighestTotalScore != null &&
        myTotalScore == secondHighestTotalScore) {
      return 0.50; // Zweitmeiste Punkte zahlen 0,50 €
    }

    return 0.0;
  }

  void _archiveAndResetScores() {
    setState(() {
      for (int i = 0; i < _players.length; i++) {
        _players[i].totalWallet += _getPlayerCurrentGameMoney(i);
      }

      for (int i = 0; i < 10; i++) {
        for (int j = 0; j < 5; j++) {
          _fixedRounds[i][j] = j < _players.length ? 0 : null;
        }
      }
    });
    _saveData(); // Ewige Kasse dauerhaft sichern!
    _showSnackBar('Spiel archiviert! Kasse wurde übernommen.');
  }

  void _clearAll() {
    setState(() {
      _players.clear();
      for (int i = 0; i < 10; i++) {
        for (int j = 0; j < 5; j++) {
          _fixedRounds[i][j] = null;
        }
      }
    });
    _saveData(); // Speicher leeren
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _openAddPlayerDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Spieler hinzufügen'),
        content: TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Name des Spielers',
            prefixIcon: Icon(Icons.person),
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: _addPlayer,
            child: const Text('Hinzufügen'),
          ),
        ],
      ),
    );
  }

  void _openEditRoundDialog(int roundIndex) {
    if (_players.isEmpty || _isGameOver)
      return; // Verhindert Eintragungen nach Spielende

    for (int i = 0; i < _players.length; i++) {
      final currentPoints = _fixedRounds[roundIndex][i];
      _scoreControllers[i].text = currentPoints == 0
          ? ''
          : (currentPoints?.toString() ?? '');
    }

    final dealerIndex = roundIndex % _players.length;
    final dealerName = _players[dealerIndex].name;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Spiel #${roundIndex + 1} eintragen'),
            const SizedBox(height: 4),
            Text(
              '🃏 Geber: $dealerName',
              style: TextStyle(
                fontSize: 14,
                color: Colors.amber[800],
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(_players.length, (index) {
              final isDealer = (index == dealerIndex);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: TextField(
                  controller: _scoreControllers[index],
                  keyboardType: TextInputType.text,
                  decoration: InputDecoration(
                    labelText:
                        _players[index].name + (isDealer ? ' (Geber 🃏)' : ''),
                    border: const OutlineInputBorder(),
                    prefixIcon: isDealer
                        ? Icon(Icons.style, color: Colors.amber[700])
                        : const Icon(Icons.edit),
                    filled: isDealer,
                    fillColor: isDealer ? Colors.amber.withOpacity(0.05) : null,
                    hintText: '0',
                  ),
                ),
              );
            }),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () => _saveRoundScores(roundIndex),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal[700],
              foregroundColor: Colors.white,
            ),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gameOver = _isGameOver;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Skajo Ewige Kasse',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
        backgroundColor: Colors.teal[700],
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          if (_players.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Spiel beenden & neues starten',
              onPressed: () => _showConfirmDialog(
                'Spiel beenden?',
                'Das aktuelle Geld wird auf das Dauerkonto gebucht und die Punkte zurückgesetzt.',
                _archiveAndResetScores,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Alles löschen',
              onPressed: () => _showConfirmDialog(
                'Komplett zurücksetzen?',
                'Spieler, Punkte und Kassenstanden werden unwiderruflich gelöscht.',
                _clearAll,
              ),
            ),
          ],
        ],
      ),
      body: _players.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.euro_symbol,
                    size: 90,
                    color: Colors.teal.withOpacity(0.25),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Keine Runde aktiv.',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Füge bis zu 5 Spieler hinzu, um den Block zu starten!',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                if (gameOver)
                  Container(
                    width: double.infinity,
                    color: Colors.red[700],
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 16,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.gavel, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'SPIEL BEENDET! Jemand hat die 100 Punkte geknackt!',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),

                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 16.0,
                        horizontal: 4.0,
                      ),
                      child: Column(
                        children: [
                          Text(
                            'GESAMTWERTUNG & KASSENSTAND',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal[800],
                              letterSpacing: 1.1,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: List.generate(_players.length, (index) {
                              final totalScore = _getPlayerTotalScore(index);
                              final currentGameMoney =
                                  _getPlayerCurrentGameMoney(index);
                              final totalWallet =
                                  _players[index].totalWallet +
                                  currentGameMoney;
                              final isNextDealer =
                                  (index == _currentDealerIndex) && !gameOver;

                              return Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                    horizontal: 2,
                                  ),
                                  decoration: isNextDealer
                                      ? BoxDecoration(
                                          border: Border.all(
                                            color: Colors.amber.shade400,
                                            width: 1.5,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          color: Colors.amber.shade50
                                              .withOpacity(0.5),
                                        )
                                      : null,
                                  child: Column(
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              _players[index].name,
                                              style: TextStyle(
                                                fontWeight: isNextDealer
                                                    ? FontWeight.bold
                                                    : FontWeight.w500,
                                                fontSize: 14,
                                                color: isNextDealer
                                                    ? Colors.amber[900]
                                                    : (totalScore >= 100
                                                          ? Colors.red[900]
                                                          : Colors.black87),
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (isNextDealer) ...[
                                            const SizedBox(width: 2),
                                            Icon(
                                              Icons.style,
                                              size: 12,
                                              color: Colors.amber[700],
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '$totalScore Pts',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: totalScore >= 100
                                              ? Colors.red[900]
                                              : (totalScore > 60
                                                    ? Colors.orange[800]
                                                    : Colors.green[700]),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '+${currentGameMoney.toStringAsFixed(2)} €',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: currentGameMoney > 0
                                              ? Colors.red[600]
                                              : Colors.grey[400],
                                        ),
                                      ),
                                      Text(
                                        'Gesamt: ${totalWallet.toStringAsFixed(2)}€',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.blueGrey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              headingRowColor: MaterialStateProperty.all(
                                Colors.teal[50],
                              ),
                              dataRowMinHeight: 48,
                              horizontalMargin: 16,
                              columnSpacing: 32,
                              showCheckboxColumn: false,
                              columns: [
                                const DataColumn(
                                  label: Text(
                                    'Spiel',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.teal,
                                    ),
                                  ),
                                ),
                                ..._players.map(
                                  (player) => DataColumn(
                                    label: Text(
                                      player.name,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.teal[900],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              rows: List.generate(10, (roundIndex) {
                                final dealerOfThisRound =
                                    roundIndex % _players.length;

                                return DataRow(
                                  onSelectChanged: gameOver
                                      ? null
                                      : (_) => _openEditRoundDialog(roundIndex),
                                  cells: [
                                    DataCell(
                                      Text(
                                        'Spiel #${roundIndex + 1}',
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    ...List.generate(_players.length, (
                                      playerIndex,
                                    ) {
                                      final val =
                                          _fixedRounds[roundIndex][playerIndex] ??
                                          0;
                                      final wasDealer =
                                          (playerIndex == dealerOfThisRound);

                                      return DataCell(
                                        Container(
                                          alignment: Alignment.centerLeft,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 4,
                                          ),
                                          decoration: wasDealer && !gameOver
                                              ? BoxDecoration(
                                                  color: Colors.amber
                                                      .withOpacity(0.12),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                )
                                              : null,
                                          child: Text(
                                            '$val' +
                                                (wasDealer && !gameOver
                                                    ? ' 🃏'
                                                    : ''),
                                            style: TextStyle(
                                              fontWeight: wasDealer
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                              color: val == 0
                                                  ? Colors.grey
                                                  : (val > 0
                                                        ? Colors.black87
                                                        : Colors.green[700]),
                                            ),
                                          ),
                                        ),
                                      );
                                    }),
                                  ],
                                );
                              }),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 80),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              if (_players.length < 5 && !gameOver)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _openAddPlayerDialog,
                    icon: const Icon(Icons.person_add),
                    label: const Text('Spieler hinzufügen'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal[700],
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showConfirmDialog(
    String title,
    String content,
    VoidCallback onConfirm,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () {
              onConfirm();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[50],
              foregroundColor: Colors.red[900],
            ),
            child: const Text('Bestätigen'),
          ),
        ],
      ),
    );
  }
}
