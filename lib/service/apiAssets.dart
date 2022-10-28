import 'dart:convert';

import 'package:app/service/index.dart';
import 'package:app/service/walletApi.dart';
import 'package:polkawallet_sdk/api/eth/apiAccountEth.dart';
import 'package:polkawallet_ui/utils/format.dart';

class ApiAssets {
  ApiAssets(this.apiRoot);

  final AppService apiRoot;

  final _tokenStakingAssetsKey = 'token_stading_';

  void setTokenStakingAssets(String pubKey, Map<String, dynamic> data) {
    apiRoot.store.storage
        .write('$_tokenStakingAssetsKey$pubKey', jsonEncode(data));
  }

  Map<String, dynamic> getTokenStakingAssets(String pubKey) {
    final tokenStakingAssets =
        apiRoot.store.storage.read('$_tokenStakingAssetsKey$pubKey');
    return tokenStakingAssets != null ? jsonDecode(tokenStakingAssets) : null;
  }

  Future<Map> updateTxs(int page) async {
    final acc = apiRoot.keyring.current;
    Map res = await apiRoot.subScan.fetchTransfersAsync(
      acc.address,
      page,
      network: apiRoot.plugin.basic.name == 'bifrost'
          ? 'bifrost-kusama'
          : apiRoot.plugin.basic.name,
    );

    if (page == 0) {
      apiRoot.store.assets.clearTxs();
    }
    // cache first page of txs
    await apiRoot.store.assets.addTxs(
      res,
      acc,
      apiRoot.plugin.basic.name,
      shouldCache: page == 0,
    );

    return res;
  }

  Future<void> fetchMarketPrices(List<String> tokens) async {
    if (tokens == null) return;

    final res = await Future.wait([
      WalletApi.getTokenPrices(tokens),
      WalletApi.getTokenPriceFromSubScan(apiRoot.plugin.basic.name)
    ]);

    final Map<String, double> prices = {
      'KUSD': 1.0,
      'AUSD': 1.0,
      'USDT': 1.0,
    };
    if ((res[1] ?? {})['data'] != null) {
      final tokenData = res[1]['data']['detail'] as Map;
      prices.addAll({
        tokenData.keys.toList()[0]:
            double.tryParse(tokenData.values.toList()[0]['price'].toString())
      });
    }

    final serverPrice = Map<String, double>.from(res[0] ?? {});
    serverPrice.removeWhere((_, value) => value == 0);
    if (serverPrice.values.length > 0) {
      prices.addAll(serverPrice);
    }

    apiRoot.store.assets.setMarketPrices(prices);
  }

  Future<void> updateStakingConfig() async {
    WalletApi.getTokenStakingConfig().then((value) {
      apiRoot.store.settings.setTokenStakingConfig(value);
    });
  }

  Future<void> updateEvmGasParams(int gasLimit,
      {bool isFixedGas = true}) async {
    EvmGasParams gasParams;
    if (isFixedGas) {
      final gasPrice = await apiRoot.plugin.sdk.api.eth.keyring.getGasPrice();
      gasParams = EvmGasParams(
          gasLimit: gasLimit, gasPrice: Fmt.balanceDouble(gasPrice, 9));
    } else {
      gasParams = await apiRoot.plugin.sdk.api.eth.account
          .queryEthGasParams(gasLimit: gasLimit);
    }

    apiRoot.store.assets.setEvmGasParams(gasParams);
  }
}
