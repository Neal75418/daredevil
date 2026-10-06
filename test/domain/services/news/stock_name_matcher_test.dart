// test/domain/services/news/stock_name_matcher_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/news/stock_name_matcher.dart';

StockMasterEntry stock(String symbol, String name) => StockMasterEntry(
  symbol: symbol,
  name: name,
  market: 'TWSE',
  industry: '電子工業',
  isActive: true,
  updatedAt: DateTime(2026, 7, 15),
);

void main() {
  late StockNameMatcher matcher;

  setUp(() {
    matcher = StockNameMatcher.fromStocks([
      stock('2330', '台積電'),
      stock('2603', '長榮'), // 2 字、在白名單
      stock('2618', '長榮航'), // 3 字
      stock('2454', '聯發科'),
      stock('1210', '大成'), // 2 字、不在白名單
      stock('2317', '鴻海'), // 2 字、在白名單
      stock('3665', '貿聯-KY'),
      stock('2882', '國泰金'),
    ]);
  });

  test('3 字以上名稱直接匹配', () {
    expect(matcher.match('台積電法說會登場'), {'2330'});
  });

  test('最長優先：長榮航不重複計入長榮', () {
    expect(matcher.match('長榮航獲利創高'), {'2618'});
  });

  test('位置消耗後其餘出現仍可匹配：標題同時有長榮航與長榮', () {
    expect(matcher.match('長榮航與長榮海運齊漲'), {'2618', '2603'});
  });

  test('聯發科不會讓白名單外的子字串重複計分', () {
    // 聯發科匹配後消耗位置；「聯發」非獨立出現
    expect(matcher.match('聯發科營收創高'), {'2454'});
  });

  test('2 字名僅白名單匹配：鴻海可、大成不可', () {
    expect(matcher.match('鴻海進軍機器人'), {'2317'});
    expect(matcher.match('明基材料醫材將成最大成長動能'), isEmpty);
  });

  test('-KY 名稱照原樣匹配', () {
    expect(matcher.match('貿聯-KY 6月營收85.18億元'), {'3665'});
  });

  test('同篇多次出現計 1（Set 語意）', () {
    expect(matcher.match('台積電漲！台積電再創高'), {'2330'});
  });

  test('無命中回空集合', () {
    expect(matcher.match('今彩539頭獎開出'), isEmpty);
  });

  test('金融股 3 字名', () {
    expect(matcher.match('國泰金股東會通過配息'), {'2882'});
  });

  test('等長名稱重疊時 tie-break 確定（字典序優先）', () {
    final m = StockNameMatcher.fromStocks([
      stock('9998', '積電子'),
      stock('9999', '台積電'),
    ]);
    // 「台積電子」中兩個 3 字名重疊：字典序「台積電」<「積電子」→ 台積電先掃並佔位
    expect(m.match('研究台積電子公司'), {'9999'});
  });

  // ====================================================================
  // 更名/併購別名(2026-08-01 熱度分析實機)
  //
  // FinMind 持續回傳已下市殭屍(2311 日月光,2018 併入 3711 日月光投控),
  // 其名稱「日月光」恰是媒體通用簡稱——殭屍吸走全部標題匹配,焦點股
  // 顯示死代碼、無漲跌幅。殭屍清理後 2311 退場,裸名「日月光」又會
  // 誰都配不到(本尊叫「日月光投控」,新聞極少寫全名)→ ASE 從熱度
  // 直接消失。別名機制:別名目標在宇宙內時蓋過同名自然入口。
  //
  // 神達(2315→3706)/永信(1716→3705)不需別名:FinMind 給本尊的名稱
  // 就是同一個短名,殭屍清理後自然接手。
  // ====================================================================
  group('別名覆蓋', () {
    test('🚨 殭屍同名並存時,別名指向本尊(2311 不得再吸走匹配)', () {
      final m = StockNameMatcher.fromStocks([
        stock('2311', '日月光'),
        stock('3711', '日月光投控'),
      ]);
      expect(m.match('日月光Q2營收創高'), {'3711'});
    });

    test('殭屍清理後(2311 已除名)裸名仍配到本尊', () {
      final m = StockNameMatcher.fromStocks([stock('3711', '日月光投控')]);
      expect(m.match('日月光法說會釋利多'), {'3711'});
    });

    test('全名出現時不重複計入(位置佔用語意不變)', () {
      final m = StockNameMatcher.fromStocks([stock('3711', '日月光投控')]);
      expect(m.match('日月光投控完成收購'), {'3711'});
    });

    test('別名目標不在宇宙 → 回退自然名(不得讓名稱憑空消失)', () {
      final m = StockNameMatcher.fromStocks([stock('2311', '日月光')]);
      expect(m.match('日月光除息'), {'2311'});
    });
  });

  test('熱度建法：match 與 matchInOrder 的命中集合相同', () {
    for (final t in ['長榮航與長榮海運齊漲', '台積電漲！台積電再創高', '今彩539頭獎開出']) {
      expect(matcher.matchInOrder(t).toSet(), matcher.match(t));
    }
  });

  group('forNewsLinks（新聞顯示用）', () {
    StockNameMatcher display(
      List<StockMasterEntry> stocks, {
      Set<String> excluded = const {},
      Set<String> phrases = const {},
    }) => StockNameMatcher.forNewsLinks(
      stocks,
      excludedNames: excluded,
      nonCompanyPhrases: phrases,
      extraAliases: const {},
    );

    test('2 字名稱預設比對得到（熱度建法比對不到）', () {
      final stocks = [stock('9901', '甲乙')];
      expect(display(stocks).match('甲乙營收創新高'), {'9901'});
      expect(StockNameMatcher.fromStocks(stocks).match('甲乙營收創新高'), isEmpty);
    });

    test('排除名稱比對不到', () {
      final m = display([stock('9902', '常見')], excluded: {'常見'});
      expect(m.match('常見問題一次看'), isEmpty);
    });

    test('非公司詞組只擋它涵蓋的位置：東南洋不算南洋、單獨的南洋照算', () {
      final m = display([stock('9911', '南洋')], phrases: {'東南洋'});
      expect(m.match('進軍東南洋布局'), isEmpty);
      expect(m.match('南洋營收創新高'), {'9911'});
    });

    test('詞組擋住跨界的 2 字名：東南洋航線不配洋航', () {
      final stocks = [stock('9912', '洋航')];
      expect(display(stocks, phrases: {'東南洋'}).match('東南洋航線運價'), isEmpty);
      // 對照：沒有詞組時會被洋航搶走
      expect(display(stocks).match('東南洋航線運價'), {'9912'});
    });

    test('同長重疊時非公司詞組優先（不靠字典序）', () {
      // 「南洋科」(U+5357) 字典序在「東南洋」(U+6771) 前；同長若依字典序，
      // 南洋科會先搶到位置
      final m = display([stock('9913', '南洋科')], phrases: {'東南洋'});
      expect(m.match('東南洋科技展'), isEmpty);
      expect(m.match('南洋科營收'), {'9913'});
    });

    test('更長的公司名蓋過較短的詞組', () {
      final m = display([stock('9914', '東南洋科技')], phrases: {'東南洋'});
      expect(m.match('東南洋科技公告'), {'9914'});
    });

    test('長名稱優先：測試電子不算測試', () {
      final m = display([stock('9907', '測試電子'), stock('9908', '測試')]);
      expect(m.match('測試電子營收'), {'9907'});
    });

    test('名稱去掉 *（熱度建法照原字串比對不到）', () {
      final stocks = [stock('9903', '丙丁*')];
      expect(display(stocks).match('丙丁股價大跌'), {'9903'});
      expect(StockNameMatcher.fromStocks(stocks).match('丙丁股價大跌'), isEmpty);
    });

    test('-KY 後綴另收基底名，全名照樣比對得到', () {
      final m = display([stock('9904', '戊己-KY')]);
      expect(m.match('戊己營收年增'), {'9904'});
      expect(m.match('戊己-KY 營收年增'), {'9904'});
    });

    test('標題用全形破折號寫後綴時，靠基底名比對得到', () {
      final m = display([stock('9904', '戊己-KY')]);
      expect(m.match('戊己－KY營收年增'), {'9904'});
    });

    test('* 與 -創 同時出現：去 * 後取基底名', () {
      final m = display([stock('9909', '辛壬*-創')]);
      expect(m.match('辛壬掛牌'), {'9909'});
    });

    test('基底名受排除清單約束，全名不受影響', () {
      final m = display([stock('9905', '常見-KY')], excluded: {'常見'});
      expect(m.match('常見問題一次看'), isEmpty);
      expect(m.match('常見-KY 公告'), {'9905'});
    });

    test('1 字名稱不比對', () {
      expect(display([stock('9906', '庚')]).match('庚公司公告'), isEmpty);
    });

    test('別名蓋過同名的自然名（殭屍代碼不吸走比對）', () {
      final m = display([stock('2311', '日月光'), stock('3711', '日月光投控')]);
      expect(m.match('日月光法說會'), {'3711'});
    });

    test('熱度別名照用：日月光指向 3711', () {
      final m = display([stock('3711', '日月光投控')]);
      expect(m.match('日月光法說會'), {'3711'});
    });

    test('matchInOrder 依標題出現位置排序、同檔只列一次', () {
      final m = display([stock('9901', '甲乙'), stock('9907', '測試電子')]);
      // 掃描順序是長名稱優先（9907 先），出現位置是甲乙在前——不排序會得到 [9907, 9901]
      expect(m.matchInOrder('甲乙與測試電子齊漲，甲乙再創高'), ['9901', '9907']);
    });

    test('namesOf 列出這檔的所有名稱（含基底名）', () {
      final m = display([stock('9904', '戊己-KY')]);
      expect(m.namesOf('9904').toSet(), {'戊己-KY', '戊己'});
      expect(m.namesOf('0000'), isEmpty);
    });

    test('nameStatusOf：有名稱／名稱全被排除／不在清單', () {
      final m = display(
        [stock('9901', '甲乙'), stock('9902', '常見')],
        excluded: {'常見'},
      );
      expect(m.nameStatusOf('9901'), StockNameStatus.matched);
      expect(m.nameStatusOf('9902'), StockNameStatus.excluded);
      expect(m.nameStatusOf('9999'), StockNameStatus.notListed);
    });
  });
}
