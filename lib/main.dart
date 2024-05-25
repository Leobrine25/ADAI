import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_tts/flutter_tts.dart';

late List<CameraDescription> _cameras;
FlutterTts flutterTts = FlutterTts();
bool ligado = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _cameras = await availableCameras();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  //varivaveis
  late CameraController controller;
  int count = 0;
  Color cor = const Color(0xFF707070);
  final String _display = "";
  late File foto;
  bool open = true;

  // Inicia as configurações do Text to speach(texto para fala);
  //
  @override
  void initState() {
    initConfigTts();
    super.initState();
    controller = CameraController(
      _cameras[0], //Sempre a camera traseira em celulares que possuem ela.
      ResolutionPreset.max,
      enableAudio: false,
    );
    controller.initialize().then((_) async {
      if (!mounted) {
        return;
      }
      setState(() {});
    }).catchError((Object e) {
      if (e is CameraException) {
        switch (e.code) {
          case 'CameraAccessDenied':
            break;
          default:
            break;
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController cameraController = controller;

    // App state changed before we got the chance to initialize.
    if (!cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      initState();
    }
  }

  //Função designada a tirar uma foto mas não salvar na memória permanentemente
  Future<void> _addImage() async {
    XFile image;
    controller.setFlashMode(FlashMode.off);
    image = await controller.takePicture();
    File file = File(image.path);
    foto = file;
    return;
  }

  //Enviar a imagem para a API ROBOFLOW e esperar retorno
  Future<void> _getResults(File file) async {
    String link =
        "https://detect.roboflow.com/adai-usjgr/3"; // link do roboflow
    List<int> imageBytes =
        file.readAsBytesSync(); //Pega a imagem tirada em _addImage
    String base64Image = base64Encode(
        imageBytes); //Encoda a imagem em base 64 necessária para a API ROBOFLOW

    Map<String, String> params = {
      'api_key':
          "", // api key PRIVADA (por isso não está aqui, mas está no APK)
      'confidence': "20", // a % de certeza de uma inferencia
    };
    Uri uri = Uri.parse(link).replace(queryParameters: params);

    var res = await http.post(
      uri,
      body: base64Image,
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
    );
    final status = res.statusCode;

    if (status != 200) {
      throw Exception('http.post error: statusCode= $status');
    }

    Map<String, dynamic> jsonRes =
        json.decode(res.body); // Decoda o json do corpo da resposta da API
    _descrever(jsonRes); // envia para descraver a imagem
    return;
  }

  //Função de descrever a imagem através do json de resposta da API para uma string
  void _descrever(Map<String, dynamic> jsonRes) {
    // Ver o Terço da largura da imagem
    int largura = jsonRes['image']['width'];
    double tercoLar = largura / 3;
    int altura = jsonRes['image']['height'];
    double tercoAlt = altura / 3;

    String fala = '';
    for (var objeto in jsonRes['predictions']) {
      switch (objeto["class"]) {
        case "Banco":
          {
            fala += ("Existe um ${objeto["class"]}");
          }
          break;
        case "bebedouro":
          {
            fala += ("Há um ${objeto["class"]}");
          }
          break;
        case "bebedouro de torneira":
          {
            fala += ("Tem um ${objeto["class"]}");
          }
          break;
        case "extintor":
          {
            fala += ("Existe um ${objeto["class"]}");
          }
          break;
        case "vaso":
          {
            fala += ("Tem um ${objeto["class"]}");
          }
          break;
        default:
          {
            fala += ("Tem uma ${objeto["class"]}");
          }
          break;
      }
      if (objeto["x"] <= tercoLar) {
        if (objeto["y"] <= tercoAlt) {
          fala += ("a sua esquerda, superior ");
        } else if (objeto["x"] >= (tercoLar * 2)) {
          fala += ("a sua esquerda, inferior ");
        } else {
          fala += ("a sua esquerda ");
        }
      }
      //Caso o X esteja entre 2/3 a 3/3 Largura, o objeto está na direita;
      else if (objeto["x"] >= (tercoLar * 2)) {
        if (objeto["y"] <= tercoAlt) {
          fala += ("a sua direita, superior");
        } else if (objeto["x"] >= (tercoLar * 2)) {
          fala += ("a sua direita, inferior");
        } else {
          fala += ("a sua direita");
        }
      }
      //Caso o X esteja entre 1/3 a 2/3Largura, o objeto está no centro;
      else if (objeto["x"] > tercoLar) {
        if (objeto["y"] <= tercoAlt) {
          fala += ("na sua frente, em cima");
        } else if (objeto["x"] >= (tercoLar * 2)) {
          fala += ("na sua frente, embaixo");
        } else {
          fala += ("na sua frente");
        }
      }
      //Caso default;
      else {
        fala += ("na sua frente");
      }
    }
    //envia para o comand de TTS
    if (fala == '') {
      fala = "nenhum dos objetos treinados foi reconhecido";
    }
    fala += (", Não há mais nenhum objeto a ser detalhado, siga a diante");
    _falar(fala);
    return;
  }

  //Dispose
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  //VIEW
  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return Container();
    }

    return MaterialApp(
      theme: ThemeData(scaffoldBackgroundColor: cor),
      home: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.grey,
          title: const Text('Adai'),
          actions: [
            Padding(
              padding:
                  const EdgeInsets.only(right: 20.0, top: 3.0, bottom: 3.0),
              child: TextButton(
                onPressed: () {
                  setState(() {
                    _falar(
                        "Botão Escanear inicia um escaneamento e após aproximadamente 5 segundos descreve os objetos a frente, Parar para a a Fala e o escaneamento");
                  });
                },
                child: Container(
                  width: 100,
                  decoration: ShapeDecoration(
                    color: Colors.orange,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Center(
                    child: Text(
                      'Ajuda',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 18,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        body: Column(children: <Widget>[
          Text(_display),
          Expanded(
              child: Stack(
            children: [
              Align(
                alignment: Alignment.center,
                child: CameraPreview(controller),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Row(children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: SizedBox(
                        height: 200,
                        width: 200,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red, // Background color
                          ),
                          //Desliga o Loop e Para a fala do TTS
                          onPressed: () {
                            _parar();
                            ligado = false;
                            open = true;
                          },
                          child: const Text('Parar!'),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: SizedBox(
                        height: 200,
                        width: 200,
                        child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green, // Background color
                            ),
                            onPressed: () {
                              //inicia a trava
                              if (open) {
                                open = false;
                                ligado = true;
                                _falaInicial();
                                _addImage().then((void nada) {
                                  _getResults(foto);
                                });
                              }
                            },
                            child: const Text('Escanear!')),
                      ),
                    ),
                  ),
                ]),
              )
            ],
          ))
        ]),
      ),
    );
  }

  //Configuração do TTS
  void initConfigTts() async {
    await flutterTts.setVolume(1.0); //0 a 1.0
    await flutterTts.setPitch(1.0); // 0.5 a 2.0
    await flutterTts.setSpeechRate(0.5); // 0.0 a 1.0
    await flutterTts.setLanguage("pt-BR"); // Linguagem
    return;
  }

  //função de Começar o TTS
  void _falar(String texto) async {
    await flutterTts.speak(texto).then((void nada) {
      if (!open) open = true;
    });
  }

  void _falaInicial() {
    flutterTts.speak("Espere dois segundos enquando analisamos a imagem");
  }

  //função de Parar o TTS
  void _parar() async {
    await flutterTts.stop();
    if (ligado) {
      _falar("Aplicativo parado");
    }
  }
}
