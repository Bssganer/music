import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.auramuzik.app.channel.audio',
    androidNotificationChannelName: 'Aura Müzik Oynatıcı',
    androidNotificationOngoing: true,
  );
  runApp(const AuraMuzikUygulamasi());
}

class AuraMuzikUygulamasi extends StatelessWidget {
  const AuraMuzikUygulamasi({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aura Müzik',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0E0E12),
        primaryColor: const Color(0xFF7C4DFF),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF7C4DFF),
          secondary: Color(0xFF00E5FF),
          surface: Color(0xFF181820),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0E0E12),
          elevation: 0,
        ),
        useMaterial3: true,
      ),
      home: const AnaEkran(),
    );
  }
}

class AnaEkran extends StatefulWidget {
  const AnaEkran({super.key});

  @override
  State<AnaEkran> createState() => _AnaEkranState();
}

class _AnaEkranState extends State<AnaEkran> {
  final OnAudioQuery _sorguMotoru = OnAudioQuery();
  final AudioPlayer _oynatici = AudioPlayer();

  List<SongModel> _tumSarkilar = [];
  List<SongModel> _aktifKuyruk = [];
  Map<String, List<int>> _calmaListeleri = {};

  String _aramaMetni = '';
  bool _izinVerildi = false;
  bool _yukleniyor = true;

  Timer? _uykuZamanlayicisi;
  int? _kalanUykuDakikasi;

  static const Set<String> _desteklenenFormatlar = {
    'mp3',
    'flac',
    'wav',
    'm4a',
  };

  @override
  void initState() {
    super.initState();
    _baslat();
  }

  Future<void> _baslat() async {
    await _listeleriYukle();
    await _izinKontrolVeTarama();
  }

  Future<void> _izinKontrolVeTarama() async {
    setState(() => _yukleniyor = true);

    PermissionStatus sesIzni = await Permission.audio.request();
    PermissionStatus depolamaIzni = await Permission.storage.request();

    bool erisimVar = sesIzni.isGranted || depolamaIzni.isGranted;

    if (!erisimVar) {
      erisimVar = await _sorguMotoru.permissionsRequest();
    }

    if (erisimVar) {
      final tarananlar = await _sorguMotoru.querySongs(
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );

      final filtrelenmis = tarananlar.where((sarki) {
        final uzanti = sarki.fileExtension.toLowerCase();
        return _desteklenenFormatlar.contains(uzanti) && (sarki.duration ?? 0) > 5000;
      }).toList();

      setState(() {
        _izinVerildi = true;
        _tumSarkilar = filtrelenmis;
        _yukleniyor = false;
      });
    } else {
      setState(() {
        _izinVerildi = false;
        _yukleniyor = false;
      });
    }
  }

  Future<void> _listeleriYukle() async {
    final prefs = await SharedPreferences.getInstance();
    final kayitliVeri = prefs.getString('aura_playlists');
    if (kayitliVeri != null) {
      final Map<String, dynamic> cozulmus = jsonDecode(kayitliVeri);
      setState(() {
        _calmaListeleri = cozulmus.map(
          (anahtar, deger) => MapEntry(anahtar, List<int>.from(deger)),
        );
      });
    }
  }

  Future<void> _listeleriKaydet() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('aura_playlists', jsonEncode(_calmaListeleri));
  }

  Future<void> _kuyruguOynat(List<SongModel> liste, int baslangicIndeksi) async {
    if (liste.isEmpty) return;
    setState(() => _aktifKuyruk = List.from(liste));

    final kaynaklar = liste.map((sarki) {
      return AudioSource.uri(
        Uri.parse(sarki.uri!),
        tag: MediaItem(
          id: sarki.id.toString(),
          album: sarki.album ?? 'Bilinmeyen Albüm',
          title: sarki.title,
          artist: sarki.artist ?? 'Bilinmeyen Sanatçı',
          artUri: Uri.parse('content://media/external/audio/albumart/${sarki.albumId}'),
        ),
      );
    }).toList();

    await _oynatici.setAudioSource(
      ConcatenatingAudioSource(children: kaynaklar),
      initialIndex: baslangicIndeksi,
    );
    _oynatici.play();
  }

  void _uykuZamanlayicisiAyarla(int? dakika) {
    _uykuZamanlayicisi?.cancel();
    if (dakika == null) {
      setState(() => _kalanUykuDakikasi = null);
      return;
    }
    setState(() => _kalanUykuDakikasi = dakika);
    _uykuZamanlayicisi = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (!mounted) return;
      if (_kalanUykuDakikasi != null && _kalanUykuDakikasi! > 1) {
        setState(() => _kalanUykuDakikasi = _kalanUykuDakikasi! - 1);
      } else {
        _oynatici.pause();
        timer.cancel();
        setState(() => _kalanUykuDakikasi = null);
      }
    });
  }

  void _uykuMenusuGoster() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF181820),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final secenekler = [15, 30, 45, 60];
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Uyku Zamanlayıcısı',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              ...secenekler.map((dk) => ListTile(
                    leading: const Icon(Icons.bedtime_outlined, color: Color(0xFF7C4DFF)),
                    title: Text('$dk Dakika'),
                    onTap: () {
                      _uykuZamanlayicisiAyarla(dk);
                      Navigator.pop(ctx);
                    },
                  )),
              if (_kalanUykuDakikasi != null)
                ListTile(
                  leading: const Icon(Icons.cancel_outlined, color: Colors.redAccent),
                  title: const Text('Zamanlayıcıyı Kapat'),
                  onTap: () {
                    _uykuZamanlayicisiAyarla(null);
                    Navigator.pop(ctx);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _yeniListeOlusturDialog() {
    final kontrolcu = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF181820),
        title: const Text('Yeni Çalma Listesi'),
        content: TextField(
          controller: kontrolcu,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Liste adı girin...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              final ad = kontrolcu.text.trim();
              if (ad.isNotEmpty && !_calmaListeleri.containsKey(ad)) {
                setState(() => _calmaListeleri[ad] = []);
                _listeleriKaydet();
              }
              Navigator.pop(ctx);
            },
            child: const Text('Oluştur'),
          ),
        ],
      ),
    );
  }

  void _sarkiyiListeyeEkleDialog(SongModel sarki) {
    if (_calmaListeleri.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Önce bir çalma listesi oluşturun.')),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF181820),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: _calmaListeleri.keys.map((listeAdi) {
            final eklendiMi = _calmaListeleri[listeAdi]!.contains(sarki.id);
            return ListTile(
              leading: Icon(
                eklendiMi ? Icons.check_circle : Icons.playlist_add,
                color: const Color(0xFF7C4DFF),
              ),
              title: Text(listeAdi),
              onTap: () {
                setState(() {
                  if (eklendiMi) {
                    _calmaListeleri[listeAdi]!.remove(sarki.id);
                  } else {
                    _calmaListeleri[listeAdi]!.add(sarki.id);
                  }
                });
                _listeleriKaydet();
                Navigator.pop(ctx);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _uykuZamanlayicisi?.cancel();
    _oynatici.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtrelenenSarkilar = _tumSarkilar.where((s) {
      final sorgu = _aramaMetni.toLowerCase();
      final baslik = s.title.toLowerCase();
      final sanatci = (s.artist ?? '').toLowerCase();
      return baslik.contains(sorgu) || sanatci.contains(sorgu);
    }).toList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Aura Müzik',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: [
            if (_kalanUykuDakikasi != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Chip(
                    label: Text('${_kalanUykuDakikasi}dk'),
                    backgroundColor: const Color(0xFF7C4DFF).withOpacity(0.25),
                  ),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.bedtime_outlined),
              onPressed: _uykuMenusuGoster,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _izinKontrolVeTarama,
            ),
          ],
          bottom: const TabBar(
            indicatorColor: Color(0xFF7C4DFF),
            tabs: [
              Tab(text: 'Tüm Şarkılar'),
              Tab(text: 'Çalma Listeleri'),
            ],
          ),
        ),
        body: _yukleniyor
            ? const Center(child: CircularProgressIndicator())
            : !_izinVerildi
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Ses dosyalarını okumak için medya izni gerekiyor.'),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _izinKontrolVeTarama,
                          child: const Text('İzin Ver'),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: TextField(
                          onChanged: (deger) => setState(() => _aramaMetni = deger),
                          decoration: InputDecoration(
                            hintText: 'Şarkı veya sanatçı ara...',
                            prefixIcon: const Icon(Icons.search),
                            filled: true,
                            fillColor: const Color(0xFF181820),
                            contentPadding: const EdgeInsets.symmetric(vertical: 0),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _sarkiListesiOlustur(filtrelenenSarkilar),
                            _calmaListeleriSekmesi(),
                          ],
                        ),
                      ),
                      _miniOynatici(),
                    ],
                  ),
      ),
    );
  }

  Widget _sarkiListesiOlustur(List<SongModel> liste) {
    if (liste.isEmpty) {
      return const Center(child: Text('Şarkı bulunamadı.'));
    }
    return ListView.builder(
      itemCount: liste.length,
      itemBuilder: (ctx, indeks) {
        final sarki = liste[indeks];
        return ListTile(
          leading: QueryArtworkWidget(
            id: sarki.id,
            type: ArtworkType.AUDIO,
            artworkBorder: BorderRadius.circular(10),
            nullArtworkWidget: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: const Color(0xFF232330),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.music_note, color: Color(0xFF7C4DFF)),
            ),
          ),
          title: Text(
            sarki.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '${sarki.artist ?? "Bilinmeyen Sanatçı"} • ${sarki.fileExtension.toUpperCase()}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => _sarkiyiListeyeEkleDialog(sarki),
          ),
          onTap: () => _kuyruguOynat(liste, indeks),
        );
      },
    );
  }

  Widget _calmaListeleriSekmesi() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF7C4DFF),
        onPressed: _yeniListeOlusturDialog,
        icon: const Icon(Icons.add),
        label: const Text('Yeni Liste'),
      ),
      body: _calmaListeleri.isEmpty
          ? const Center(child: Text('Henüz çalma listesi oluşturmadınız.'))
          : ListView(
              children: _calmaListeleri.entries.map((girdi) {
                final listeAdi = girdi.key;
                final idListesi = girdi.value;
                final listedekiSarkilar = _tumSarkilar
                    .where((s) => idListesi.contains(s.id))
                    .toList();

                return ExpansionTile(
                  leading: const Icon(Icons.queue_music, color: Color(0xFF00E5FF)),
                  title: Text(
                    listeAdi,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('${listedekiSarkilar.length} şarkı'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.play_circle_fill, color: Color(0xFF7C4DFF)),
                        onPressed: listedekiSarkilar.isEmpty
                            ? null
                            : () => _kuyruguOynat(listedekiSarkilar, 0),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: () {
                          setState(() => _calmaListeleri.remove(listeAdi));
                          _listeleriKaydet();
                        },
                      ),
                    ],
                  ),
                  children: listedekiSarkilar.asMap().entries.map((eleman) {
                    final sarkiIndeksi = eleman.key;
                    final sarki = eleman.value;
                    return ListTile(
                      title: Text(sarki.title, maxLines: 1),
                      subtitle: Text(sarki.artist ?? 'Bilinmeyen Sanatçı', maxLines: 1),
                      onTap: () => _kuyruguOynat(listedekiSarkilar, sarkiIndeksi),
                    );
                  }).toList(),
                );
              }).toList(),
            ),
    );
  }

  Widget _miniOynatici() {
    return StreamBuilder<int?>(
      stream: _oynatici.currentIndexStream,
      builder: (ctx, snapshot) {
        final indeks = snapshot.data;
        if (indeks == null || indeks >= _aktifKuyruk.length) {
          return const SizedBox.shrink();
        }
        final aktifSarki = _aktifKuyruk[indeks];

        return GestureDetector(
          onTap: _tamEkranOynaticiAc,
          child: Container(
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF7C4DFF).withOpacity(0.4)),
            ),
            child: Row(
              children: [
                QueryArtworkWidget(
                  id: aktifSarki.id,
                  type: ArtworkType.AUDIO,
                  artworkWidth: 46,
                  artworkHeight: 46,
                  artworkBorder: BorderRadius.circular(10),
                  nullArtworkWidget: const Icon(Icons.music_note, size: 36, color: Color(0xFF7C4DFF)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        aktifSarki.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        aktifSarki.artist ?? 'Bilinmeyen Sanatçı',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.skip_previous),
                  onPressed: _oynatici.hasPrevious ? _oynatici.seekToPrevious : null,
                ),
                StreamBuilder<bool>(
                  stream: _oynatici.playingStream,
                  builder: (ctx, durum) {
                    final oynuyor = durum.data ?? false;
                    return IconButton(
                      icon: Icon(oynuyor ? Icons.pause_circle : Icons.play_circle, size: 36),
                      color: const Color(0xFF7C4DFF),
                      onPressed: oynuyor ? _oynatici.pause : _oynatici.play,
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  onPressed: _oynatici.hasNext ? _oynatici.seekToNext : null,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _tamEkranOynaticiAc() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0E0E12),
      builder: (ctx) {
        return StreamBuilder<int?>(
          stream: _oynatici.currentIndexStream,
          builder: (ctx, snapshot) {
            final indeks = snapshot.data;
            if (indeks == null || indeks >= _aktifKuyruk.length) {
              return const SizedBox.shrink();
            }
            final sarki = _aktifKuyruk[indeks];

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down, size: 32),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                      const Text('Şimdi Çalıyor', style: TextStyle(fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.bedtime_outlined),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _uykuMenusuGoster();
                        },
                      ),
                    ],
                  ),
                  QueryArtworkWidget(
                    id: sarki.id,
                    type: ArtworkType.AUDIO,
                    artworkWidth: 260,
                    artworkHeight: 260,
                    artworkBorder: BorderRadius.circular(24),
                    nullArtworkWidget: Container(
                      width: 260,
                      height: 260,
                      decoration: BoxDecoration(
                        color: const Color(0xFF181820),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Icon(Icons.album, size: 110, color: Color(0xFF7C4DFF)),
                    ),
                  ),
                  Column(
                    children: [
                      Text(
                        sarki.title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        sarki.artist ?? 'Bilinmeyen Sanatçı',
                        style: const TextStyle(fontSize: 16, color: Colors.white60),
                      ),
                    ],
                  ),
                  StreamBuilder<Duration>(
                    stream: _oynatici.positionStream,
                    builder: (ctx, posSnap) {
                      final konum = posSnap.data ?? Duration.zero;
                      final toplam = _oynatici.duration ?? Duration.zero;
                      final maksSaniye = toplam.inSeconds > 0 ? toplam.inSeconds.toDouble() : 1.0;
                      final mevcutSaniye = konum.inSeconds.toDouble().clamp(0.0, maksSaniye);

                      return Column(
                        children: [
                          Slider(
                            value: mevcutSaniye,
                            max: maksSaniye,
                            activeColor: const Color(0xFF7C4DFF),
                            onChanged: (deger) {
                              _oynatici.seek(Duration(seconds: deger.toInt()));
                            },
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_sureBicimlendir(konum)),
                                Text(_sureBicimlendir(toplam)),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      StreamBuilder<bool>(
                        stream: _oynatici.shuffleModeEnabledStream,
                        builder: (ctx, shufSnap) {
                          final acik = shufSnap.data ?? false;
                          return IconButton(
                            icon: Icon(
                              Icons.shuffle,
                              color: acik ? const Color(0xFF00E5FF) : Colors.white54,
                            ),
                            onPressed: () => _oynatici.setShuffleModeEnabled(!acik),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_previous, size: 40),
                        onPressed: _oynatici.hasPrevious ? _oynatici.seekToPrevious : null,
                      ),
                      StreamBuilder<bool>(
                        stream: _oynatici.playingStream,
                        builder: (ctx, playSnap) {
                          final oynuyor = playSnap.data ?? false;
                          return IconButton(
                            icon: Icon(
                              oynuyor ? Icons.pause_circle_filled : Icons.play_circle_filled,
                              size: 72,
                              color: const Color(0xFF7C4DFF),
                            ),
                            onPressed: oynuyor ? _oynatici.pause : _oynatici.play,
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next, size: 40),
                        onPressed: _oynatici.hasNext ? _oynatici.seekToNext : null,
                      ),
                      StreamBuilder<LoopMode>(
                        stream: _oynatici.loopModeStream,
                        builder: (ctx, loopSnap) {
                          final mod = loopSnap.data ?? LoopMode.off;
                          IconData ikon = Icons.repeat;
                          Color renk = Colors.white54;
                          if (mod == LoopMode.all) {
                            renk = const Color(0xFF00E5FF);
                          } else if (mod == LoopMode.one) {
                            ikon = Icons.repeat_one;
                            renk = const Color(0xFF00E5FF);
                          }
                          return IconButton(
                            icon: Icon(ikon, color: renk),
                            onPressed: () {
                              final siradaki = mod == LoopMode.off
                                  ? LoopMode.all
                                  : mod == LoopMode.all
                                      ? LoopMode.one
                                      : LoopMode.off;
                              _oynatici.setLoopMode(siradaki);
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _sureBicimlendir(Duration d) {
    final dk = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sn = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$dk:$sn';
  }
}
