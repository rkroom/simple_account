import 'package:flutter_test/flutter_test.dart';
import 'package:simple_account/widgets/quick_select.dart';

void main() {
  group('calculateQuickSelectDividerTop', () {
    test('centers the divider after one visible category row', () {
      final top = calculateQuickSelectDividerTop(
        width: 360,
        height: 255,
        categoryItemCount: 3,
        accountItemCount: 1,
      );

      expect(top, closeTo(90.92, 0.01));
    });

    test('places the divider between a full category grid and accounts', () {
      final top = calculateQuickSelectDividerTop(
        width: 360,
        height: 255,
        categoryItemCount: 6,
        accountItemCount: 6,
      );

      expect(top, closeTo(122.58, 0.01));
    });

    test('hides the divider when either section is empty', () {
      expect(
        calculateQuickSelectDividerTop(
          width: 360,
          height: 255,
          categoryItemCount: 0,
          accountItemCount: 2,
        ),
        isNull,
      );
      expect(
        calculateQuickSelectDividerTop(
          width: 360,
          height: 255,
          categoryItemCount: 2,
          accountItemCount: 0,
        ),
        isNull,
      );
    });

    test('hides the divider when the category grid fills the top half', () {
      expect(
        calculateQuickSelectDividerTop(
          width: 411,
          height: 255,
          categoryItemCount: 6,
          accountItemCount: 6,
        ),
        isNull,
      );
    });
  });
}
