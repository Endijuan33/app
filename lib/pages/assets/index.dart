import 'dart:async';

import 'package:app/common/components/CustomRefreshIndicator.dart';
import 'package:app/common/consts.dart';
import 'package:app/common/types/pluginDisabled.dart';
import 'package:app/pages/assets/asset/assetPage.dart';
import 'package:app/pages/assets/manage/manageAssetsPage.dart';
import 'package:app/pages/assets/transfer/transferPage.dart';
import 'package:app/pages/networkSelectPage.dart';
import 'package:app/pages/public/AdBanner.dart';
import 'package:app/service/index.dart';
import 'package:app/utils/InstrumentWidget.dart';
import 'package:app/utils/i18n/index.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:polkawallet_plugin_acala/common/constants/base.dart';
import 'package:polkawallet_plugin_karura/common/constants/base.dart';
import 'package:polkawallet_sdk/api/types/networkParams.dart';
import 'package:polkawallet_sdk/plugin/index.dart';
import 'package:polkawallet_sdk/plugin/store/balances.dart';
import 'package:polkawallet_sdk/utils/i18n.dart';
import 'package:polkawallet_ui/components/textTag.dart';
import 'package:polkawallet_ui/components/tokenIcon.dart';
import 'package:polkawallet_ui/components/v3/addressIcon.dart';
import 'package:polkawallet_ui/components/v3/borderedTitle.dart';
import 'package:polkawallet_ui/components/v3/dialog.dart';
import 'package:polkawallet_ui/components/v3/index.dart' as v3;
import 'package:polkawallet_ui/components/v3/roundedCard.dart';
import 'package:polkawallet_ui/pages/accountQrCodePage.dart';
import 'package:polkawallet_ui/pages/scanPage.dart';
import 'package:polkawallet_ui/utils/format.dart';
import 'package:polkawallet_ui/utils/i18n.dart';
import 'package:polkawallet_ui/utils/index.dart';
import 'package:rive/rive.dart';
import 'package:sticky_headers/sticky_headers.dart';

final assetsType = [
  "All",
  "Native",
  "ERC-20",
  "Cross-chain",
  "LP Tokens",
  "Taiga token"
];

class AssetsPage extends StatefulWidget {
  AssetsPage(
    this.service,
    this.plugins,
    this.connectedNode,
    this.checkJSCodeUpdate,
    this.disabledPlugins,
    this.changeNetwork,
  );

  final AppService service;
  final NetworkParams connectedNode;
  final Future<void> Function(PolkawalletPlugin) checkJSCodeUpdate;
  // final Function(String) handleWalletConnect;

  final List<PolkawalletPlugin> plugins;
  final List<PluginDisabled> disabledPlugins;
  final Future<void> Function(PolkawalletPlugin) changeNetwork;

  @override
  _AssetsState createState() => _AssetsState();
}

class _AssetsState extends State<AssetsPage> {
  final GlobalKey<CustomRefreshIndicatorState> _refreshKey =
      new GlobalKey<CustomRefreshIndicatorState>();
  bool _refreshing = false;

  Timer _priceUpdateTimer;

  int instrumentIndex = 0;

  double _rate = 1.0;

  int _assetsTypeIndex = 0;

  ScrollController _scrollController;

  Future<void> _updateBalances() async {
    if (widget.connectedNode == null) return;

    setState(() {
      _refreshing = true;
    });
    await widget.service.plugin.updateBalances(widget.service.keyring.current);
    if (mounted) {
      setState(() {
        _refreshing = false;
      });
    }
  }

  Future<void> _updateMarketPrices() async {
    widget.service.assets
        .fetchMarketPrices(widget.service.plugin.networkState.tokenSymbol);

    final duration =
        widget.service.store.assets.marketPrices.keys.length > 0 ? 60 : 6;
    _priceUpdateTimer = Timer(Duration(seconds: duration), _updateMarketPrices);
  }

  Future<void> _handleScan() async {
    final dic = I18n.of(context).getDic(i18n_full_dic_app, 'account');
    final data = (await Navigator.pushNamed(
      context,
      ScanPage.route,
      arguments: 'tx',
    )) as QRCodeResult;
    if (data != null) {
      if (data.type == QRCodeResultType.rawData &&
          data.rawData.substring(0, 3) == 'wc:') {
        if (widget.service.keyring.current.observation == true) {
          showCupertinoDialog(
              context: context,
              builder: (_) {
                return PolkawalletAlertDialog(
                  type: DialogType.warn,
                  content: Text(dic['wc.ob.invalid']),
                  actions: [
                    PolkawalletActionSheetAction(
                      isDefaultAction: true,
                      child: Text(I18n.of(context)
                          .getDic(i18n_full_dic_ui, 'common')['ok']),
                      onPressed: () => Navigator.of(context).pop(),
                    )
                  ],
                );
              });
          return;
        }
        widget.service.wc.initWalletConnect(context, data.rawData);
        return;
      }

      if (data.type == QRCodeResultType.address) {
        if (data.address.chainType == "substrate") {
          if (widget.service.plugin.basic.name == para_chain_name_karura ||
              widget.service.plugin.basic.name == para_chain_name_acala) {
            final symbol =
                (widget.service.plugin.networkState.tokenSymbol ?? [''])[0];
            Navigator.of(context).pushNamed('/assets/token/transfer',
                arguments: {
                  'tokenNameId': symbol,
                  'address': data.address.address
                });
            return;
          }
          Navigator.of(context).pushNamed(
            TransferPage.route,
            arguments: TransferPageParams(address: data.address.address),
          );
        }
        return;
      }
    }
  }

  @override
  void didUpdateWidget(covariant AssetsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectedNode?.endpoint != widget.connectedNode?.endpoint) {
      if (_refreshing) {
        _refreshKey.currentState.dismiss(CustomRefreshIndicatorMode.canceled);
        if (mounted) {
          setState(() {
            _refreshing = false;
          });
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();

    _scrollController = ScrollController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateMarketPrices();
      _getRate();
    });
  }

  Future<void> _getRate() async {
    var rate = await widget.service.store.settings.getRate();
    if (mounted) {
      setState(() {
        this._rate = rate;
      });
    }
  }

  @override
  void dispose() {
    _priceUpdateTimer?.cancel();

    super.dispose();
  }

  List<Color> _gradienColors() {
    switch (widget.service.plugin.basic.name) {
      case para_chain_name_karura:
        return [Color(0xFFFF4646), Color(0xFFFF5D4D), Color(0xFF323133)];
      case para_chain_name_acala:
        return [Color(0xFFFF5D3A), Color(0xFFFF3F3F), Color(0xFF4528FF)];
      case para_chain_name_bifrost:
        return [
          Color(0xFF5AAFE1),
          Color(0xFF596ED2),
          Color(0xFFB358BD),
          Color(0xFFFFAE5E)
        ];
      default:
        return [Theme.of(context).primaryColor, Theme.of(context).hoverColor];
    }
  }

  List<InstrumentData> _instrumentDatas() {
    final List<InstrumentData> datas = [];

    final dic = I18n.of(context).getDic(i18n_full_dic_app, 'assets');
    final symbol = (widget.service.plugin.networkState.tokenSymbol ?? [''])[0];
    final title = "${dic['v3.my']} $symbol";

    final instrument1 = InstrumentData(0, [], title: title);

    final decimals =
        (widget.service.plugin.networkState.tokenDecimals ?? [12])[0];
    var marketPrice = widget.service.store.assets.marketPrices[symbol] ?? 0;
    if (widget.service.store.settings.priceCurrency != "USD") {
      marketPrice *= _rate;
    }
    final available = marketPrice *
        Fmt.bigIntToDouble(
          Fmt.balanceInt(
              (widget.service.plugin.balances.native?.availableBalance ?? 0)
                  .toString()),
          decimals,
        );

    final reserved = marketPrice *
        Fmt.bigIntToDouble(
          Fmt.balanceInt(
              (widget.service.plugin.balances.native?.reservedBalance ?? 0)
                  .toString()),
          decimals,
        );

    final locked = marketPrice *
        Fmt.bigIntToDouble(
          Fmt.balanceInt(
              (widget.service.plugin.balances.native?.lockedBalance ?? 0)
                  .toString()),
          decimals,
        );

    InstrumentData totalBalance =
        InstrumentData(available + reserved + locked, [], title: title);
    totalBalance.items
        .add(InstrumentItemData(Color(0xFFFF7647), dic['reserved'], reserved));
    totalBalance.items
        .add(InstrumentItemData(Color(0xFFFFC952), dic['locked'], locked));
    totalBalance.items.add(
        InstrumentItemData(Color(0xFF7D97EE), dic['available'], available));

    datas.add(instrument1);
    datas.add(totalBalance);
    datas.add(instrument1);

    return datas;
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      systemOverlayStyle: UI.isDarkTheme(context)
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            margin: EdgeInsets.only(right: 8.w),
            child: AddressIcon(widget.service.keyring.current.address,
                svg: widget.service.keyring.current.icon),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                Fmt.address(widget.service.keyring.current.address),
                style: Theme.of(context).textTheme.headline5,
              ),
              Container(
                color: Colors.transparent,
                margin: EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    widget.connectedNode == null
                        ? Container(
                            width: 9,
                            height: 9,
                            margin: EdgeInsets.only(right: 4),
                            child: Center(
                                child: RiveAnimation.asset(
                              'assets/images/connecting.riv',
                            )))
                        : Container(
                            width: 9,
                            height: 9,
                            margin: EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                                color: UI.isDarkTheme(context)
                                    ? Color(0xFF82FF99)
                                    : Color(0xFF7D97EE),
                                borderRadius:
                                    BorderRadius.all(Radius.circular(5.5))),
                          ),
                    Text(
                      widget.service.plugin.basic.name.toUpperCase(),
                      style: Theme.of(context)
                          .textTheme
                          .headline4
                          .copyWith(fontWeight: FontWeight.w600, height: 1.1),
                    ),
                    const SizedBox(width: 8)
                  ],
                ),
              )
            ],
          ),
        ],
      ),
      centerTitle: true,
      backgroundColor: Colors.transparent,
      elevation: 0.0,
      leading: Padding(
          padding: EdgeInsets.only(left: 16.w),
          child: Row(children: [
            v3.IconButton(
              isBlueBg: true,
              icon: SvgPicture.asset(
                "assets/images/icon_car.svg",
                color: UI.isDarkTheme(context) ? Colors.black : Colors.white,
                height: 22,
              ),
              onPressed: () async {
                final selected = (await Navigator.of(context)
                    .pushNamed(NetworkSelectPage.route)) as PolkawalletPlugin;
                if (!mounted) return;

                setState(() {});
                if (selected != null &&
                    selected.basic.name != widget.service.plugin.basic.name) {
                  widget.checkJSCodeUpdate(selected);
                }
              },
            )
          ])),
      actions: <Widget>[
        Container(
            margin: EdgeInsets.only(right: 6.w),
            child: v3.PopupMenuButton(
                offset: Offset(-12, 52),
                color: UI.isDarkTheme(context)
                    ? Color(0xA63A3B3D)
                    : Theme.of(context).cardColor,
                padding: EdgeInsets.zero,
                elevation: 3,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: Color(0x21FFFFFF), width: 0.5),
                  borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(10),
                      bottomLeft: Radius.circular(10),
                      bottomRight: Radius.circular(10)),
                ),
                onSelected: (value) {
                  if (widget.service.keyring.current.address != '') {
                    if (value == '0') {
                      _handleScan();
                    } else {
                      Navigator.pushNamed(context, AccountQrCodePage.route);
                    }
                  }
                },
                itemBuilder: (BuildContext context) {
                  return <v3.PopupMenuEntry<String>>[
                    v3.PopupMenuItem(
                      height: 34,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                              padding: EdgeInsets.only(left: 2),
                              child: SvgPicture.asset(
                                'assets/images/scan.svg',
                                color: UI.isDarkTheme(context)
                                    ? Colors.white
                                    : Color(0xFF979797),
                                width: 20,
                              )),
                          Padding(
                            padding: EdgeInsets.only(left: 5),
                            child: Text(
                              I18n.of(context)
                                  .getDic(i18n_full_dic_app, 'assets')['scan'],
                              style: Theme.of(context).textTheme.headline5,
                            ),
                          )
                        ],
                      ),
                      value: '0',
                    ),
                    v3.PopupMenuDivider(height: 1.0),
                    v3.PopupMenuItem(
                      height: 34,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SvgPicture.asset(
                            'assets/images/qr.svg',
                            color: UI.isDarkTheme(context)
                                ? Colors.white
                                : Color(0xFF979797),
                            width: 22,
                          ),
                          Padding(
                            padding: EdgeInsets.only(left: 5),
                            child: Text(
                              I18n.of(context).getDic(
                                  i18n_full_dic_app, 'assets')['QRCode'],
                              style: Theme.of(context).textTheme.headline5,
                            ),
                          )
                        ],
                      ),
                      value: '1',
                    ),
                  ];
                },
                icon: v3.IconButton(
                  icon: Icon(
                    Icons.add,
                    color: UI.isDarkTheme(context)
                        ? Colors.white
                        : Theme.of(context).disabledColor,
                    size: 20,
                  ),
                ))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        final symbol =
            (widget.service.plugin.networkState.tokenSymbol ?? [''])[0];
        final decimals =
            (widget.service.plugin.networkState.tokenDecimals ?? [12])[0];

        final balancesInfo = widget.service.plugin.balances.native;
        final tokens = widget.service.plugin.balances.tokens.toList();
        final tokensAll = widget.service.plugin.noneNativeTokensAll ?? [];
        final defaultTokens = widget.service.plugin.defaultTokens;

        // filter tokens by plugin.defaultTokens
        if (defaultTokens.length > 0) {
          tokens.retainWhere((e) =>
              e.symbol.contains('-') ||
              defaultTokens.indexOf(e.tokenNameId) > -1);
        }
        // remove empty LP tokens
        if (tokens.length > 0) {
          tokens.removeWhere((e) => e.symbol.contains('-') && e.amount == '0');
        }
        // add custom assets from user's config & tokensAll
        final customTokensConfig = widget.service.store.assets.customAssets;
        final isStateMint =
            widget.service.plugin.basic.name == para_chain_name_statemine ||
                widget.service.plugin.basic.name == para_chain_name_statemint;
        if (customTokensConfig.keys.length > 0) {
          tokens.retainWhere(
              (e) => customTokensConfig[isStateMint ? e.id : e.symbol]);

          tokensAll.retainWhere(
              (e) => customTokensConfig[isStateMint ? e.id : e.symbol]);
          tokensAll.forEach((e) {
            if (tokens.indexWhere((token) => token.symbol == e.symbol) < 0) {
              tokens.add(e);
            }
          });
        }
        // sort the list
        if (tokens.length > 0) {
          // remove native token
          tokens.removeWhere((element) => element.symbol == symbol);
          tokens.sort((a, b) => a.symbol.contains('-')
              ? 1
              : b.symbol.contains('-')
                  ? -1
                  : a.symbol.compareTo(b.symbol));
        }

        final extraTokens = widget.service.plugin.balances.extraTokens;
        final isTokensFromCache =
            widget.service.plugin.balances.isTokensFromCache;

        String tokenPrice;
        if (widget.service.store.assets.marketPrices[symbol] != null &&
            balancesInfo != null) {
          tokenPrice = Fmt.priceCeil(
              widget.service.store.assets.marketPrices[symbol] *
                  (widget.service.store.settings.priceCurrency != "USD"
                      ? _rate
                      : 1.0) *
                  Fmt.bigIntToDouble(Fmt.balanceTotal(balancesInfo), decimals));
        }

        if (widget.service.plugin.basic.name != plugin_name_karura &&
            widget.service.plugin.basic.name != plugin_name_acala) {
          _assetsTypeIndex = 0;
        }

        if (_assetsTypeIndex != 0) {
          var type = "Token";
          if (assetsType[_assetsTypeIndex] == "Cross-chain") {
            type = "ForeignAsset";
          } else if (assetsType[_assetsTypeIndex] == "Taiga token") {
            type = "TaigaAsset";
          } else if (assetsType[_assetsTypeIndex] == "LP Tokens") {
            type = "DexShare";
          } else if (assetsType[_assetsTypeIndex] == "ERC-20") {
            type = "Erc20";
          }
          tokens.retainWhere((element) => element.type == type);
        }

        return Scaffold(
          resizeToAvoidBottomInset: false,
          appBar: _buildAppBar(),
          body: CustomRefreshIndicator(
              edgeOffset: 16,
              key: _refreshKey,
              onRefresh: _updateBalances,
              child: ListView(controller: _scrollController, children: [
                StickyHeader(
                    header: Container(),
                    content: Column(
                      children: <Widget>[
                        Padding(
                          padding: EdgeInsets.fromLTRB(16.w, 15.h, 16.w, 10.h),
                          child: instrumentIndex == 0 ||
                                  widget.service.plugin
                                          .getAggregatedAssetsWidget(
                                              onSwitchBack: null,
                                              onSwitchHideBalance: null) ==
                                      null
                              ? InstrumentWidget(
                                  _instrumentDatas(),
                                  gradienColors: _gradienColors(),
                                  switchDefi: widget.service.plugin
                                          .getAggregatedAssetsWidget(
                                              onSwitchBack: null,
                                              onSwitchHideBalance: null) !=
                                      null,
                                  onSwitchChange: () {
                                    setState(() {
                                      instrumentIndex = 1;
                                    });
                                  },
                                  onSwitchHideBalance: () {
                                    widget.service.store.settings
                                        .setIsHideBalance(!widget.service.store
                                            .settings.isHideBalance);
                                  },
                                  enabled: widget.connectedNode != null,
                                  hideBalance: widget
                                      .service.store.settings.isHideBalance,
                                  priceCurrency: widget
                                      .service.store.settings.priceCurrency,
                                  key: Key(
                                      "${widget.service.keyring.current.address}_${widget.service.plugin.basic.name}"),
                                )
                              : widget.service.plugin.getAggregatedAssetsWidget(
                                  onSwitchBack: () {
                                    setState(() {
                                      instrumentIndex = 0;
                                    });
                                  },
                                  onSwitchHideBalance: () {
                                    widget.service.store.settings
                                        .setIsHideBalance(!widget.service.store
                                            .settings.isHideBalance);
                                  },
                                  priceCurrency: widget
                                      .service.store.settings.priceCurrency,
                                  rate: _rate,
                                  hideBalance: widget
                                      .service.store.settings.isHideBalance),
                        ),
                        Container(
                          margin: EdgeInsets.only(left: 16.w, right: 16.w),
                          child: AdBanner(widget.service, widget.connectedNode),
                        ),
                        // Container(
                        //   margin: EdgeInsets.only(left: 16.w, right: 16.w),
                        //   child: RoundedButton(
                        //     text: 'DApps Test',
                        //     onPressed: () =>
                        //         Navigator.of(context).pushNamed(DAppsTestPage.route),
                        //   ),
                        // ),
                        // Container(
                        //   margin: EdgeInsets.only(left: 16.w, right: 16.w),
                        //   child: RoundedButton(
                        //     text: 'Bridge Test',
                        //     onPressed: () => Navigator.of(context)
                        //         .pushNamed(BridgeTestPage.route),
                        //   ),
                        // ),
                        widget.service.plugin.basic.isTestNet
                            ? Padding(
                                padding: EdgeInsets.only(top: 5.h),
                                child: Row(
                                  children: [
                                    Expanded(
                                        child: TextTag(
                                      I18n.of(context).getDic(i18n_full_dic_app,
                                          'assets')['assets.warn'],
                                      color: Colors.deepOrange,
                                      fontSize: UI.getTextSize(12, context),
                                      margin: EdgeInsets.all(0),
                                      padding: EdgeInsets.all(8),
                                    ))
                                  ],
                                ),
                              )
                            : Container(height: 0.h),
                        Container(
                          margin: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 0),
                          child: Divider(height: 1),
                        ),
                      ],
                    )),
                StickyHeader(
                    header: Container(
                        padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 12.h),
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: Column(
                          children: [
                            Row(
                              children: [
                                BorderedTitle(
                                  title: I18n.of(context).getDic(
                                      i18n_full_dic_app, 'assets')['assets'],
                                ),
                                Visibility(
                                    visible: (widget.service.plugin
                                                    .noneNativeTokensAll ??
                                                [])
                                            .length >
                                        0,
                                    child: Expanded(
                                        child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        v3.IconButton(
                                          onPressed: () => Navigator.of(context)
                                              .pushNamed(
                                                  ManageAssetsPage.route),
                                          icon: Icon(
                                            Icons.menu,
                                            color:
                                                Theme.of(context).disabledColor,
                                            size: 20,
                                          ),
                                        )
                                      ],
                                    )))
                              ],
                            ),
                            Visibility(
                                visible: widget.service.plugin.basic.name ==
                                        plugin_name_karura ||
                                    widget.service.plugin.basic.name ==
                                        plugin_name_acala,
                                child: Container(
                                    height: 30,
                                    width: double.infinity,
                                    margin: EdgeInsets.only(top: 8),
                                    child: ListView.separated(
                                        scrollDirection: Axis.horizontal,
                                        itemBuilder: (context, index) {
                                          final child = Center(
                                            child: Text(assetsType[index],
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .button
                                                    ?.copyWith(
                                                        color:
                                                            _assetsTypeIndex ==
                                                                    index
                                                                ? Theme.of(
                                                                        context)
                                                                    .textTheme
                                                                    .button
                                                                    ?.color
                                                                : Theme.of(
                                                                        context)
                                                                    .textTheme
                                                                    .headline1
                                                                    ?.color,
                                                        fontSize:
                                                            UI.getTextSize(
                                                                10, context))),
                                          );
                                          return CupertinoButton(
                                            padding: EdgeInsets.all(0),
                                            onPressed: () {
                                              _scrollController.animateTo(0,
                                                  duration: Duration(
                                                      milliseconds: 500),
                                                  curve: Curves.ease);
                                              setState(() {
                                                _assetsTypeIndex = index;
                                              });
                                            },
                                            child: Container(
                                              height: 24,
                                              width: 65,
                                              child: UI.isDarkTheme(context) &&
                                                      _assetsTypeIndex != index
                                                  ? RoundedCard(
                                                      radius: 6, child: child)
                                                  : Container(
                                                      width: double.infinity,
                                                      height: double.infinity,
                                                      decoration: BoxDecoration(
                                                        borderRadius:
                                                            _assetsTypeIndex ==
                                                                    index
                                                                ? null
                                                                : BorderRadius
                                                                    .all(Radius
                                                                        .circular(
                                                                            6.0)),
                                                        color: _assetsTypeIndex ==
                                                                index
                                                            ? Colors.transparent
                                                            : UI.isDarkTheme(
                                                                    context)
                                                                ? Color(
                                                                    0x14FFFFFF)
                                                                : Colors.white,
                                                        border:
                                                            _assetsTypeIndex ==
                                                                    index
                                                                ? null
                                                                : Border.all(
                                                                    color: Color(
                                                                        0xFF979797),
                                                                    width: 0.2,
                                                                  ),
                                                        image: _assetsTypeIndex ==
                                                                index
                                                            ? DecorationImage(
                                                                image: AssetImage(
                                                                    'assets/images/icon_select_btn${UI.isDarkTheme(context) ? "_dark" : ""}.png'),
                                                                fit:
                                                                    BoxFit.fill,
                                                              )
                                                            : null,
                                                        boxShadow:
                                                            _assetsTypeIndex ==
                                                                    index
                                                                ? []
                                                                : [
                                                                    BoxShadow(
                                                                      offset:
                                                                          Offset(
                                                                              1,
                                                                              1),
                                                                      blurRadius:
                                                                          1,
                                                                      spreadRadius:
                                                                          0,
                                                                      color: Color(
                                                                          0x30000000),
                                                                    ),
                                                                  ],
                                                      ),
                                                      child: child,
                                                    ),
                                            ),
                                          );
                                        },
                                        separatorBuilder: (context, index) =>
                                            Container(width: 9),
                                        itemCount: assetsType.length)))
                          ],
                        )),
                    content: Container(
                      child: ListView(
                        shrinkWrap: true,
                        physics: NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.only(bottom: 6.h, top: 3.h),
                        children: [
                          RoundedCard(
                            margin: EdgeInsets.only(left: 16.w, right: 16.w),
                            child: Column(
                              children: [
                                Visibility(
                                    visible: _assetsTypeIndex == 0 ||
                                        _assetsTypeIndex == 1,
                                    child: ListTile(
                                      horizontalTitleGap: 10,
                                      leading: Container(
                                        child: TokenIcon(
                                          symbol,
                                          widget.service.plugin.tokenIcons,
                                          size: 30,
                                        ),
                                      ),
                                      title: Text(
                                        symbol,
                                        style: Theme.of(context)
                                            .textTheme
                                            .headline5
                                            .copyWith(
                                                fontWeight: FontWeight.w600,
                                                fontSize: UI.getTextSize(
                                                    18, context)),
                                      ),
                                      trailing: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                              balancesInfo != null &&
                                                      balancesInfo.freeBalance !=
                                                          null
                                                  ? widget
                                                          .service
                                                          .store
                                                          .settings
                                                          .isHideBalance
                                                      ? "******"
                                                      : Fmt.priceFloorBigInt(
                                                          Fmt.balanceTotal(
                                                              balancesInfo),
                                                          decimals,
                                                          lengthFixed: 4)
                                                  : '--.--',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .headline5
                                                  .copyWith(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: balancesInfo?.isFromCache ==
                                                              false
                                                          ? Theme.of(context)
                                                              .textTheme
                                                              .headline1
                                                              .color
                                                          : Theme.of(context)
                                                              .dividerColor)),
                                          Text(
                                            widget.service.store.settings
                                                    .isHideBalance
                                                ? "******"
                                                : '≈ ${Fmt.priceCurrencySymbol(widget.service.store.settings.priceCurrency)}${tokenPrice ?? '--.--'}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .headline6
                                                .copyWith(
                                                    fontFamily:
                                                        UI.getFontFamily(
                                                            'TitilliumWeb',
                                                            context)),
                                          ),
                                        ],
                                      ),
                                      onTap: () {
                                        Navigator.pushNamed(
                                            context, AssetPage.route);
                                      },
                                    )),
                                Visibility(
                                    visible:
                                        tokens != null && tokens.length > 0,
                                    child: Column(
                                      children: (tokens ?? [])
                                          .map((TokenBalanceData i) {
                                        // we can use token price form plugin or from market
                                        final price = (i.getPrice != null
                                                ? i.getPrice()
                                                : i.price) ??
                                            widget.service.store.assets
                                                .marketPrices[i.symbol] ??
                                            0.0;
                                        return TokenItem(
                                          i,
                                          i.decimals,
                                          isFromCache: isTokensFromCache,
                                          detailPageRoute: i.detailPageRoute,
                                          marketPrice: price,
                                          icon: TokenIcon(
                                            isStateMint ? i.id : i.symbol,
                                            widget.service.plugin.tokenIcons,
                                            symbol: i.symbol,
                                            size: 30,
                                          ),
                                          isHideBalance: widget.service.store
                                              .settings.isHideBalance,
                                          priceCurrency: widget.service.store
                                              .settings.priceCurrency,
                                          priceRate: _rate,
                                        );
                                      }).toList(),
                                    )),
                                Visibility(
                                  visible: extraTokens == null ||
                                      extraTokens.length == 0,
                                  child: Column(
                                      children: (extraTokens ?? [])
                                          .map((ExtraTokenData i) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Padding(
                                          padding: EdgeInsets.only(top: 16.h),
                                          child: BorderedTitle(
                                            title: i.title,
                                          ),
                                        ),
                                        Column(
                                          children: i.tokens
                                              .map((e) => TokenItem(
                                                    e,
                                                    e.decimals,
                                                    isFromCache:
                                                        isTokensFromCache,
                                                    detailPageRoute:
                                                        e.detailPageRoute,
                                                    icon: widget.service.plugin
                                                        .tokenIcons[e.symbol],
                                                    isHideBalance: widget
                                                        .service
                                                        .store
                                                        .settings
                                                        .isHideBalance,
                                                    priceCurrency: widget
                                                        .service
                                                        .store
                                                        .settings
                                                        .priceCurrency,
                                                    priceRate: _rate,
                                                  ))
                                              .toList(),
                                        )
                                      ],
                                    );
                                  }).toList()),
                                )
                              ],
                            ),
                          ),
                        ],
                      ),
                    ))
              ])),
        );
      },
    );
  }
}

class TokenItem extends StatelessWidget {
  TokenItem(this.item, this.decimals,
      {this.marketPrice,
      this.detailPageRoute,
      this.icon,
      this.isFromCache = false,
      this.isHideBalance,
      this.priceCurrency,
      this.priceRate});
  final TokenBalanceData item;
  final int decimals;
  final double marketPrice;
  final String detailPageRoute;
  final Widget icon;
  final bool isFromCache;
  final bool isHideBalance;
  final String priceCurrency;
  final double priceRate;

  @override
  Widget build(BuildContext context) {
    final balanceTotal =
        Fmt.balanceInt(item.amount) + Fmt.balanceInt(item.reserved);
    return Column(
      children: [
        Divider(height: 1),
        ListTile(
          horizontalTitleGap: 10,
          leading: Container(
            child: icon ??
                CircleAvatar(
                  child: Text(item.symbol.substring(0, 2)),
                ),
          ),
          title: Text(
            item.name,
            style: Theme.of(context).textTheme.headline5.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: UI.getTextSize(18, context)),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                isHideBalance
                    ? "******"
                    : Fmt.priceFloorBigInt(balanceTotal, decimals,
                        lengthFixed: 4),
                style: Theme.of(context).textTheme.headline5.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isFromCache == false
                        ? Theme.of(context).textTheme.headline1.color
                        : Theme.of(context).dividerColor),
              ),
              marketPrice != null && marketPrice > 0
                  ? Text(
                      isHideBalance
                          ? "******"
                          : '≈ ${Fmt.priceCurrencySymbol(priceCurrency)}${Fmt.priceFloor(Fmt.bigIntToDouble(balanceTotal, decimals) * marketPrice * priceRate)}',
                      style: Theme.of(context).textTheme.headline6.copyWith(
                          fontFamily:
                              UI.getFontFamily('TitilliumWeb', context)),
                    )
                  : Container(height: 0, width: 8),
            ],
          ),
          onTap: detailPageRoute == null
              ? null
              : () {
                  Navigator.of(context).pushNamed(detailPageRoute,
                      arguments: item
                        ..priceCurrency = priceCurrency
                        ..priceRate = priceRate);
                },
        )
      ],
    );
  }
}
