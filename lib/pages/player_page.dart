import 'dart:convert';
import 'dart:io';

import 'package:better_player/better_player.dart';
import 'package:clicli_dark/api/post.dart';
import 'package:clicli_dark/config.dart';
import 'package:clicli_dark/instance.dart';
import 'package:clicli_dark/pages/search_page.dart';
import 'package:clicli_dark/utils/reg_utils.dart';
import 'package:clicli_dark/utils/toast_utils.dart';
import 'package:clicli_dark/widgets/common_widget.dart';
import 'package:clicli_dark/widgets/loading2load.dart' show loadingWidget;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

//https://stackoverflow.com/questions/52431109/flutter-video-player-fullscreen
class PlayerPage extends StatefulWidget with WidgetsBindingObserver {
  PlayerPage({Key key, this.data, this.pos}) : super(key: key);

  final Map data;
  final int pos;

  @override
  State<StatefulWidget> createState() {
    return _PlayerPageState();
  }
}

//https://vt1.doubanio.com/201902111139/0c06a85c600b915d8c9cbdbbaf06ba9f/view/movie/M/302420330.mp4
class _PlayerPageState extends State<PlayerPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  TabController _tabController;

  String thumbnail;
  bool isLoading = true;
  List videoList = [];
  Map videoSrc = {};
  int currPlayIndex = 0;
  bool showDownloadIcon = false;

  Future<String> getVideoSrc(String _src, int i) async {
    if (videoSrc[i] == null) {
      final _videoSrc = (await getPlayUrl(_src)).data;
      videoSrc[i] = jsonDecode(_videoSrc)['url'];
    }
    return videoSrc[i];
  }

  getDetail() async {
    thumbnail = getSuo(widget.data['content']);
    videoList =
        jsonDecode((await getVideoList(widget.data['id'])).data)['videos'] ??
            [];

    print(videoList);
    if (mounted) {
      if (videoList.length > 0) {
        setState(() {
//          Screen.keepOn(true);
          WidgetsBinding.instance.addObserver(this);
          _tabController = TabController(length: 2, vsync: this);
          isLoading = false;
        });
        setHistory();
        await initPlayer();
        widget.data['pv'] =
            jsonDecode((await getPV(widget.data['id'])).data)['result']['pv'];
        setState(() {});
      } else {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  BetterPlayerController _betterPlayerController;

  initPlayer() async {
    final String src =
        await getVideoSrc(videoList[currPlayIndex]['content'], currPlayIndex);

    final BetterPlayerDataSource betterPlayerDataSource =
        BetterPlayerDataSource(BetterPlayerDataSourceType.NETWORK, src);

    _betterPlayerController = BetterPlayerController(
      BetterPlayerConfiguration(
        showControlsOnInitialize: true,
        autoPlay: true,
        aspectRatio: 16 / 9,
        controlsConfiguration: BetterPlayerControlsConfiguration(
          iconsColor: Colors.white,
          enableMute: false,
          controlBarColor: Colors.black.withOpacity(0.4),
          enableProgressText: true,
          controlBarDecoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.black.withOpacity(0.5), Colors.transparent],
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
            ),
          ),
          controlAppBarDecoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.transparent, Colors.black.withOpacity(0.5)],
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
            ),
          ),
        ),
      ),
      betterPlayerDataSource: betterPlayerDataSource,
    );

    _betterPlayerController
        .setupAppBarTitle('${videoList[currPlayIndex]['title']}');

    if (currPlayIndex > 0) showSnackBar('已自动定位到上次播放剧集');
    setHistory();
  }

  toggleVideo(int i) async {
    if (i == currPlayIndex) return;

    if (_betterPlayerController == null) {
      // 网络错误 || 加载失败
      currPlayIndex = i;
      initPlayer();
      return;
    }

    print(videoList[i]);

    _betterPlayerController.setupAppBarTitle('${videoList[i]['title']}');
    final String src = await getVideoSrc(videoList[i]['content'], i);
    _betterPlayerController
        .setupDataSource(
            BetterPlayerDataSource(BetterPlayerDataSourceType.NETWORK, src))
        .then((value) {
      setState(() {
        currPlayIndex = i;
      });
    });

    setHistory();
  }

  setHistory() async {
    // Instances.sp.remove('history');
    final List o = jsonDecode(Instances.sp.getString('history') ?? '[]');
    bool hasHis = false;
    for (int i = 0; i < o.length; i++) {
      if (o[i]['id'] == widget.data['id']) {
        o[i]['time'] = DateTime.now().millisecondsSinceEpoch;
        o[i]['curr'] = currPlayIndex;
        o[i]['name'] = videoList[currPlayIndex]['title'];
        o[i]['data'] = widget.data;
        hasHis = true;
        break;
      }
    }

    if (!hasHis) {
      final historyInfo = {
        'curr': currPlayIndex,
        'thumb': getSuo(widget.data['content']),
        'name': videoList[currPlayIndex]['title'],
        'id': widget.data['id'],
        'data': widget.data,
        'time': DateTime.now().millisecondsSinceEpoch
      };
      o.add(historyInfo);
    }
    Instances.sp.setString('history', jsonEncode(o));
  }

  @override
  void initState() {
    super.initState();
    if (widget.pos != null) {
      currPlayIndex = widget.pos;
    } else {
      final historyList = jsonDecode(Instances.sp.getString('history') ?? '[]');
      if (historyList != null && historyList.length > 0) {
        final history = historyList.firstWhere(
          (his) => his['id'] == widget.data['id'],
          orElse: () => null,
        );
        if (history != null) currPlayIndex = history['curr'];
      }
    }
    getDetail();
    getFollowBgi();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.paused:
        if (await _betterPlayerController.isPlaying())
          _betterPlayerController.pause();
        break;
      default:
        if (await _betterPlayerController.isPlaying())
          _betterPlayerController.play();
        break;
    }
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }

  _dispose() {
    _betterPlayerController?.dispose();
    _tabController?.dispose();
    WidgetsBinding.instance?.removeObserver(this);
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(statusBarColor: Colors.transparent),
    );
//    Screen.keepOn(false);
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return Scaffold(body: Center(child: loadingWidget));
    final detail = widget.data;
    return AnnotatedRegion(
      value: videoList.length > 0
          ? SystemUiOverlayStyle(
              statusBarColor: Colors.black,
              statusBarIconBrightness: Brightness.light,
              systemNavigationBarIconBrightness: Brightness.light,
              systemNavigationBarColor: Colors.black,
            )
          : SystemUiOverlayStyle(
              statusBarColor: Colors.white,
              statusBarIconBrightness: Brightness.dark,
              systemNavigationBarIconBrightness: Brightness.dark,
              systemNavigationBarColor: Colors.white,
            ),
      child: Scaffold(
          appBar: videoList.length < 1
              ? AppBar(
                  title: Text(
                    detail['title'],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  actions: <Widget>[
                    IconButton(
                      icon: Icon(Icons.more_horiz),
                      onPressed: () {
                        showSnackBar('come soon ···');
                      },
                    )
                  ],
                )
              : null,
          body: SafeArea(
            child: videoList.length > 0
                ? Column(
                    children: <Widget>[
                      _betterPlayerController != null
                          ? BetterPlayer(controller: _betterPlayerController)
                          : AspectRatio(
                              aspectRatio: 16 / 9,
                              child: Container(
                                color: Colors.black,
                                child: Center(
                                    child: Text(
                                  'loading ···',
                                  style: TextStyle(color: Colors.white),
                                )),
                              ),
                            ),
                      Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            boxShadow: [
                              BoxShadow(
                                color: Theme.of(context)
                                    .accentColor
                                    .withOpacity(0.2),
                                offset: Offset(0, 10),
                                blurRadius: 12,
                                spreadRadius: -10,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              TabBar(
                                tabs: <Widget>[
                                  Tab(text: '剧集'),
                                  Tab(text: '简介')
                                ],
                                controller: _tabController,
                                isScrollable: true,
                                indicatorSize: TabBarIndicatorSize.tab,
                                labelColor: Theme.of(context).accentColor,
                                indicatorPadding: EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 0),
                                labelStyle: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                                unselectedLabelStyle: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                              GestureDetector(
                                onDoubleTap: () {
                                  setState(() {
                                    showDownloadIcon = !showDownloadIcon;
                                  });
                                },
                                child: Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 10),
                                  child: ClipOval(
                                    child: Image.network(
                                      getAvatar(avatar: detail['uqq'] ?? ''),
                                      width: 35,
                                      height: 35,
                                    ),
                                  ),
                                ),
                              )
                            ],
                          )),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: <Widget>[
                            buildProfile(context),
                            PlayerProfile(detail, videoList.length > 0)
                          ],
                        ),
                      )
                    ],
                  )
                : PlayerProfile(detail, videoList.length > 0),
          )),
    );
  }

  bool hasFollowBgi = false;

  getFollowBgi() {
    final List o = jsonDecode(Instances.sp.getString('followBgi') ?? '[]');

    for (int i = 0; i < o.length; i++) {
      if (o[i]['id'] == widget.data['id']) {
        hasFollowBgi = true;
        return;
      }
    }
  }

  followBgi() {
    // Instances.sp.remove('followBgi');
    final List o = jsonDecode(Instances.sp.getString('followBgi') ?? '[]');

    if (hasFollowBgi) {
      o.removeWhere((f) => f['id'] == widget.data['id']);
    } else {
      final historyInfo = {
        'thumb': getSuo(widget.data['content']),
        'name': widget.data['title'],
        'id': widget.data['id'],
        'data': widget.data,
        'time': DateTime.now().millisecondsSinceEpoch
      };
      o.add(historyInfo);
    }

    hasFollowBgi = !hasFollowBgi;
    Instances.sp.setString('followBgi', jsonEncode(o));
    setState(() {});
  }

  Widget buildProfile(BuildContext context) {
    final detail = widget.data;
    final theme = Theme.of(context);
    final caption = theme.textTheme.caption;
    final List tags = detail['tag'].substring(1).split(' ');
    final time = DateTime.parse(detail['time']);
    final m = time.month < 10 ? '0${time.month}' : time.month;
    final d = time.day < 10 ? '0${time.day}' : time.day;
    return Container(
        child: ListView(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              ellipsisText(detail['title']),
              InkWell(
                onTap: followBgi,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  color: theme.accentColor.withOpacity(0.4),
                  child: Text(
                    hasFollowBgi ? '已追番' : '追番',
                    style: TextStyle(color: theme.accentColor),
                  ),
                ),
              )
            ],
          ),
          SizedBox(height: 10),
          Row(
            children: <Widget>[
              Text('GV${widget.data['id']}  ', style: caption),
              Text(' $m-$d  ', style: caption),
              Icon(Icons.whatshot, size: 12, color: theme.accentColor),
              Text('${detail['pv']?.toString() ?? 0} ℃',
                  style: caption.copyWith(color: theme.accentColor)),
            ],
          ),
          SizedBox(height: 10),
          Row(children: [
            for (int i = 0; i < tags.length; i++)
              if (tags[i].length > 0)
                GestureDetector(
                  onTap: () async {
                    if (await _betterPlayerController.isPlaying())
                      _betterPlayerController.pause();
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (BuildContext context) =>
                            TagPage(tags[i] as String)));
                  },
                  onDoubleTap: () async {
                    if (await _betterPlayerController.isPlaying())
                      _betterPlayerController.pause();

                    Navigator.of(context).pop();
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (BuildContext context) =>
                            TagPage(tags[i] as String)));
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.all(Radius.circular(4)),
                      color: Theme.of(context).accentColor.withOpacity(0.2),
                    ),
                    margin: EdgeInsets.symmetric(horizontal: 2),
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(
                      tags[i],
                      style: TextStyle(
                        color: Theme.of(context).accentColor.withOpacity(0.6),
                      ),
                    ),
                  ),
                )
          ]),
          SizedBox(height: 10),
          buildVideoList()
        ]));
  }

  Widget buildVideoList() {
    final color = Theme.of(context).accentColor;
    return Column(
        children: List.generate(videoList.length, (int i) {
      return Container(
        margin: EdgeInsets.symmetric(vertical: 5),
        child: InkWell(
            splashColor: color.withOpacity(0.6),
            highlightColor: color.withOpacity(0.4),
            onTap: () {
              toggleVideo(i);
            },
            child: Container(
              color: i == currPlayIndex
                  ? color.withOpacity(0.5)
                  : color.withOpacity(0.2),
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(
                children: <Widget>[
                  Text(
                    '  ${videoList[i]['oid']}  ',
                    style: TextStyle(color: color),
                  ),
                  Expanded(
                    child: ellipsisText(
                      '${videoList[i]['title']}',
                      style: TextStyle(color: color),
                    ),
                  ),
                  if (showDownloadIcon)
                    InkWell(
                      child: Icon(Icons.file_download, color: color),
                      onTap: () {
                        downloadByUrl(videoList[i]['content'],
                            fileName:
                                '${videoList[i]['oid']}${videoList[i]['title']}');
                      },
                    )
                ],
              ),
            )),
      );
    }));
  }

  Future<void> downloadByUrl(String url, {String fileName}) async {
    final path = await Config.downloadPath();
    final downloadPath = Directory('$path/${widget.data['title']}');
    if (!downloadPath.existsSync()) downloadPath.createSync();

    final tasks = await FlutterDownloader.loadTasks();
    if (tasks.any((task) => task.filename == fileName)) {
      showSnackBar('正在下载···');
      return;
    }

    showSnackBar('开始下载···');
    await FlutterDownloader.enqueue(
      url: url,
      savedDir: downloadPath.path,
      showNotification: true,
      openFileFromNotification: true,
      fileName: fileName,
    );
  }
}

class PlayerProfile extends StatefulWidget {
  PlayerProfile(this.detail, this.needTitle);

  final Map detail;
  final bool needTitle;

  @override
  State<StatefulWidget> createState() => _PlayerProfile();
}

class _PlayerProfile extends State<PlayerProfile>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final detail = widget.detail;
    final i = detail['content'].indexOf('# 播放出错');
    final content =
        i < 0 ? detail['content'] : detail['content'].substring(0, i);
    final meta =
        '''${widget.needTitle ? '# ${detail['title']} \r\n ' : ''}> ${detail['uname'] ?? ''}  ${detail['time']}   GV${detail['id']} \r\n#  ''';
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: MarkdownBody(
          // selectable: true,
          data: meta + content,
          onTapLink: (url) async {
            showDialog<Null>(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: Text('提示'),
                    content: Text('是否使用外部打开该链接？\r\n\r\n $url'),
                    actions: <Widget>[
                      FlatButton(
                        child: Text('取消'),
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                      ),
                      FlatButton(
                        child: Text('确定'),
                        onPressed: () async {
                          if (await canLaunch(url)) {
                            await launch(url);
                          } else {
                            showErrorSnackBar('打开链接失败');
                          }
                          Navigator.of(context).pop();
                        },
                      ),
                    ],
                  );
                });
          },
          styleSheetTheme: MarkdownStyleSheetBaseTheme.platform,
          styleSheet: MarkdownStyleSheet(
            blockquotePadding: EdgeInsets.fromLTRB(10.0, 0, 0, 0),
            blockquoteDecoration: BoxDecoration(
              border: Border(
                  left: BorderSide(
                width: 2.0,
                color: Theme.of(context).accentColor,
              )),
            ),
            code: TextStyle(fontFamily: "Source Code Pro"),
            a: TextStyle(color: Theme.of(context).accentColor),
          )),
    );
  }
}
