
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

void main() {
  runApp(const PrevisaoTempoApp());
}

class PrevisaoTempoApp extends StatelessWidget {
  const PrevisaoTempoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Previsão do Tempo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const TelaInicial(),
    );
  }
}

class Cidade {
  final String nome;
  final String uf;
  final String id;

  Cidade({required this.nome, required this.uf, required this.id});
}

class DiaPrevisao {
  final String data;
  final String tempo;
  final String maxima;
  final String minima;
  final String iuv;

  DiaPrevisao({
    required this.data,
    required this.tempo,
    required this.maxima,
    required this.minima,
    required this.iuv,
  });
}

class CptecService {
  static const String baseUrl = 'https://servicos.cptec.inpe.br/XML';

  static const Map<String, String> condicoes = {
    'ec': 'Encoberto com chuvas isoladas',
    'ci': 'Chuvas isoladas',
    'c': 'Chuva',
    'in': 'Instável',
    'pp': 'Possibilidade de pancadas de chuva',
    'cm': 'Chuva pela manhã',
    'cn': 'Chuva à noite',
    'pt': 'Pancadas de chuva à tarde',
    'pm': 'Pancadas de chuva pela manhã',
    'np': 'Nublado e pancadas de chuva',
    'pc': 'Pancadas de chuva',
    'pn': 'Parcialmente nublado',
    'cv': 'Chuvisco',
    'ch': 'Chuvoso',
    't': 'Tempestade',
    'ps': 'Predomínio de sol',
    'e': 'Encoberto',
    'n': 'Nublado',
    'cl': 'Céu claro',
    'nv': 'Nevoeiro',
    'g': 'Geada',
    'ne': 'Neve',
    'nd': 'Não definido',
    'pnt': 'Pancadas de chuva à noite',
    'psc': 'Possibilidade de chuva',
    'pcm': 'Possibilidade de chuva pela manhã',
    'pct': 'Possibilidade de chuva à tarde',
    'pcn': 'Possibilidade de chuva à noite',
    'npt': 'Nublado com pancadas à tarde',
    'npn': 'Nublado com pancadas à noite',
    'ncn': 'Nublado com possibilidade de chuva à noite',
    'nct': 'Nublado com possibilidade de chuva à tarde',
    'ncm': 'Nublado com possibilidade de chuva pela manhã',
    'npm': 'Nublado com pancadas pela manhã',
    'npp': 'Nublado com possibilidade de chuva',
    'vn': 'Variação de nebulosidade',
  };

  static String removerAcentos(String texto) {
    const comAcento = 'áàãâéêíóôõúüç';
    const semAcento = 'aaaaeeiooouuc';

    String resultado = texto.toLowerCase();

    for (int i = 0; i < comAcento.length; i++) {
      resultado = resultado.replaceAll(
        comAcento[i],
        semAcento[i],
      );
    }

    return resultado;
  }

  static String campo(XmlElement elemento, String nome) {
    final encontrados = elemento.findElements(nome);
    if (encontrados.isEmpty) return '';
    return encontrados.first.innerText.trim();
  }

  static Future<List<Cidade>> buscarCidades(String nome) async {
    final pesquisa = removerAcentos(nome.trim());

    final url = Uri.parse(
      '$baseUrl/listaCidades?city=${Uri.encodeComponent(pesquisa)}',
    );

    final resposta = await http.get(url);

    if (resposta.statusCode != 200) {
      throw Exception('Não foi possível consultar as cidades.');
    }

    final documento = XmlDocument.parse(resposta.body);

    return documento.findAllElements('cidade').map((elemento) {
      return Cidade(
        nome: campo(elemento, 'nome'),
        uf: campo(elemento, 'uf'),
        id: campo(elemento, 'id'),
      );
    }).toList();
  }

  static Future<Map<String, dynamic>> buscarPrevisao(
    Cidade cidade,
  ) async {
    final url = Uri.parse(
      '$baseUrl/cidade/${cidade.id}/previsao.xml',
    );

    final resposta = await http.get(url);

    if (resposta.statusCode != 200) {
      throw Exception('Não foi possível consultar a previsão.');
    }

    final documento = XmlDocument.parse(resposta.body);
    final raiz = documento.rootElement;

    final dias = documento.findAllElements('previsao').map((elemento) {
      return DiaPrevisao(
        data: campo(elemento, 'dia'),
        tempo: campo(elemento, 'tempo'),
        maxima: campo(elemento, 'maxima'),
        minima: campo(elemento, 'minima'),
        iuv: campo(elemento, 'iuv'),
      );
    }).toList();

    return {
      'nome': campo(raiz, 'nome'),
      'uf': campo(raiz, 'uf'),
      'atualizacao': campo(raiz, 'atualizacao'),
      'dias': dias,
    };
  }
}

class TelaInicial extends StatefulWidget {
  const TelaInicial({super.key});

  @override
  State<TelaInicial> createState() => _TelaInicialState();
}

class _TelaInicialState extends State<TelaInicial> {
  final TextEditingController controlador = TextEditingController();

  List<Cidade> cidades = [];
  Cidade? cidadeSelecionada;
  Map<String, dynamic>? previsao;

  bool carregando = false;
  String mensagem = '';

  @override
  void initState() {
    super.initState();
    carregarUltimaCidade();
  }

  Future<void> carregarUltimaCidade() async {
    final preferencias = await SharedPreferences.getInstance();
    final nome = preferencias.getString('ultimaCidade');

    if (nome != null && nome.isNotEmpty) {
      controlador.text = nome;
    }
  }

  Future<void> pesquisarCidade() async {
    if (controlador.text.trim().isEmpty) {
      setState(() => mensagem = 'Digite o nome de uma cidade.');
      return;
    }

    setState(() {
      carregando = true;
      mensagem = '';
      cidades = [];
      previsao = null;
    });

    try {
      final resultado = await CptecService.buscarCidades(
        controlador.text,
      );

      setState(() {
        cidades = resultado;
        if (resultado.isEmpty) {
          mensagem = 'Nenhuma cidade encontrada.';
        }
      });
    } catch (erro) {
      setState(() {
        mensagem = 'Erro ao buscar cidades. Verifique sua conexão.';
      });
    } finally {
      setState(() => carregando = false);
    }
  }

  Future<void> selecionarCidade(Cidade cidade) async {
    setState(() {
      cidadeSelecionada = cidade;
      cidades = [];
      carregando = true;
      mensagem = '';
      previsao = null;
    });

    final preferencias = await SharedPreferences.getInstance();
    await preferencias.setString('ultimaCidade', cidade.nome);

    await atualizarPrevisao();
  }

  Future<void> atualizarPrevisao() async {
    if (cidadeSelecionada == null) return;

    setState(() {
      carregando = true;
      mensagem = '';
    });

    try {
      final resultado = await CptecService.buscarPrevisao(
        cidadeSelecionada!,
      );

      setState(() {
        previsao = resultado;

        if ((resultado['dias'] as List).isEmpty) {
          mensagem = 'Não há previsão disponível para esta cidade.';
        }
      });
    } catch (erro) {
      setState(() {
        mensagem = 'Erro ao carregar a previsão. Tente novamente.';
      });
    } finally {
      setState(() => carregando = false);
    }
  }

  IconData iconeTempo(String codigo) {
    if (['c', 'ci', 'cv', 'ch', 'pc', 't', 'ec'].contains(codigo)) {
      return Icons.umbrella;
    }
    if (['n', 'e', 'np', 'pn', 'vn'].contains(codigo)) {
      return Icons.cloud;
    }
    if (codigo == 'nv') return Icons.foggy;
    return Icons.wb_sunny;
  }

  String formatarData(String data) {
    try {
      return DateFormat('dd/MM/yyyy').format(DateTime.parse(data));
    } catch (_) {
      return data.isEmpty ? 'Data indisponível' : data;
    }
  }

  Widget cartaoPrevisao(DiaPrevisao dia) {
    final descricao =
        CptecService.condicoes[dia.tempo] ?? 'Condição não identificada';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 7),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              iconeTempo(dia.tempo),
              size: 38,
              color: Colors.blue,
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatarData(dia.data),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(descricao),
                  Text('Mínima: ${dia.minima.isEmpty ? '--' : dia.minima} °C'),
                  Text('Máxima: ${dia.maxima.isEmpty ? '--' : dia.maxima} °C'),
                  Text('Índice UV: ${dia.iuv.isEmpty ? 'Não informado' : dia.iuv}'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget graficoTemperaturas(List<DiaPrevisao> dias) {
    final dados = dias.where((dia) {
      return double.tryParse(dia.maxima) != null &&
          double.tryParse(dia.minima) != null;
    }).toList();

    if (dados.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Temperaturas previstas',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  barGroups: List.generate(dados.length, (index) {
                    final dia = dados[index];

                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: double.parse(dia.minima),
                          color: Colors.lightBlue,
                          width: 12,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        BarChartRodData(
                          toY: double.parse(dia.maxima),
                          color: Colors.orange,
                          width: 12,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ],
                    );
                  }),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= dados.length) {
                            return const SizedBox.shrink();
                          }
                          return Text(
                            DateFormat('dd/MM').format(
                              DateTime.parse(dados[index].data),
                            ),
                            style: const TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Text(
              'Azul: mínima | Laranja: máxima',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dias = previsao == null
        ? <DiaPrevisao>[]
        : previsao!['dias'] as List<DiaPrevisao>;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Previsão do Tempo'),
        centerTitle: true,
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 750),
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              const Text(
                'Encontre sua cidade',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controlador,
                decoration: InputDecoration(
                  hintText: 'Digite o nome da cidade',
                  prefixIcon: const Icon(Icons.location_city),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: carregando ? null : pesquisarCidade,
                  ),
                ),
                onSubmitted: (_) => pesquisarCidade(),
              ),
              const SizedBox(height: 12),
              if (carregando) const LinearProgressIndicator(),
              if (mensagem.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    mensagem,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ...cidades.map((cidade) {
                return ListTile(
                  leading: const Icon(Icons.location_on),
                  title: Text(cidade.nome),
                  subtitle: Text(cidade.uf),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () => selecionarCidade(cidade),
                );
              }),
              if (previsao != null) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${previsao!['nome']} - ${previsao!['uf']}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: carregando ? null : atualizarPrevisao,
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Atualizar previsão',
                    ),
                  ],
                ),
                Text('Atualização: ${previsao!['atualizacao']}'),
                const SizedBox(height: 12),
                ...dias.map(cartaoPrevisao),
                if (dias.isNotEmpty) graficoTemperaturas(dias),
                const SizedBox(height: 20),
                const Text(
                  'Fonte dos dados: CPTEC/INPE',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    controlador.dispose();
    super.dispose();
  }
}
