import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/news_link_params.dart';

void main() {
  test('排除名稱與非公司詞組至少 2 字、彼此不重疊', () {
    for (final n in [
      ...NewsLinkParams.excludedNames,
      ...NewsLinkParams.nonCompanyPhrases,
    ]) {
      expect(
        n.length,
        greaterThanOrEqualTo(NewsLinkParams.minNameLength),
        reason: n,
      );
    }
    expect(
      NewsLinkParams.excludedNames.intersection(
        NewsLinkParams.nonCompanyPhrases,
      ),
      isEmpty,
    );
  });
}
