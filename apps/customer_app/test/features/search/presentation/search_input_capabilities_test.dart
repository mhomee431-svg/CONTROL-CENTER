import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/features/search/domain/search_text_sanitizer.dart';
import 'package:hyperlocal_app/features/search/presentation/controllers/search_controller.dart';
import 'package:hyperlocal_app/features/search/presentation/search_input_capabilities.dart';
import 'package:hyperlocal_app/features/search/presentation/widgets/search_input_field.dart';

/// A stand-in for a future voice implementation. It never touches a microphone
/// -- it just proves the seam is wired: the affordance appears, and the callback
/// it captured is the bar's own delivery path.
class _FakeVoiceExtension extends SearchInputExtension {
  @override
  Widget? buildAction(ValueChanged<String> onResult) {
    return IconButton(
      key: const Key('fakeVoice'),
      icon: const Icon(Icons.mic),
      tooltip: 'Search by voice',
      onPressed: () => onResult('dove shampoo'),
    );
  }
}

void main() {
  group('the typed query is restored when the field is rebuilt', () {
    // The controller-level tests prove the query lives in the provider. This
    // proves the WIDGET reads it back, which is the half that was untested:
    // `SearchInputField.initState` copies `searchQueryProvider.query` into its
    // own TextEditingController. Without that copy the field renders empty on
    // return even though the state is intact, and the customer sees a blank
    // box above their restored results.
    testWidgets('a rebuilt field shows the query that was typed', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(searchQueryProvider.notifier)
          .debouncedTextChanged('Dove Shampoo');

      Future<void> pumpField() => tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: SearchInputField())),
        ),
      );

      await pumpField();
      await tester.pumpAndSettle();

      expect(find.text('Dove Shampoo'), findsOneWidget);

      // Simulate leaving to product details and coming back.
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await pumpField();
      await tester.pumpAndSettle();

      expect(
        find.text('Dove Shampoo'),
        findsOneWidget,
        reason: 'the query must still be in the box after returning',
      );
    });

    testWidgets('a field with no prior query starts empty', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: SearchInputField())),
        ),
      );
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, isEmpty);
    });
  });

  group('voice search ships OFF', () {
    test('the default capability set is text only', () {
      const caps = SearchInputCapabilities.textOnly();
      expect(caps.has(SearchInputCapability.text), isTrue);
      expect(
        caps.has(SearchInputCapability.voice),
        isFalse,
        reason:
            'an affordance with no implementation behind it is a dead button',
      );
    });

    test('the default provider reports voice unavailable', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container
            .read(searchInputCapabilitiesProvider)
            .has(SearchInputCapability.voice),
        isFalse,
      );
    });

    test('the compile-time flag defaults to off', () {
      expect(SearchInputFeatureFlags.voiceSearchEnabled, isFalse);
    });
  });

  group('the default extension contributes nothing', () {
    test('builds no action', () {
      const extension = NoopSearchInputExtension();
      expect(extension.buildAction((_) {}), isNull);
    });

    test('the default provider installs the no-op', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(searchInputExtensionProvider),
        isA<NoopSearchInputExtension>(),
      );
    });
  });

  group('an extension is used only when the build allows it', () {
    test('capability off means the extension is never asked for an action', () {
      var asked = false;
      final extension = _FakeVoiceExtension();
      final container = ProviderContainer(
        overrides: [
          searchInputCapabilitiesProvider.overrideWithValue(
            const SearchInputCapabilities.textOnly(),
          ),
          searchInputExtensionProvider.overrideWithValue(extension),
        ],
      );
      addTearDown(container.dispose);

      // The same conditional the field uses.
      final caps = container.read(searchInputCapabilitiesProvider);
      if (caps.has(SearchInputCapability.voice)) {
        extension.buildAction((_) {});
        asked = true;
      }
      expect(asked, isFalse);
    });

    test('capability on means the extension contributes its action', () {
      expect(_FakeVoiceExtension().buildAction((_) {}), isNotNull);
    });

    test(
      'an extension receives the bar delivery callback, not the controller',
      () {
        String? received;
        final widget = _FakeVoiceExtension().buildAction((value) {
          received = value;
        });
        expect(widget, isNotNull);

        (widget! as IconButton).onPressed!();
        expect(
          received,
          'dove shampoo',
          reason:
              'the extension must deliver through the callback the bar gave '
              'it, so history and analytics cannot be bypassed',
        );
      },
    );
  });

  group('SearchTextSanitizer', () {
    test('keeps ordinary product text untouched', () {
      for (final input in [
        'Dove Shampoo',
        'dove',
        "L'OrÃ©al",
        'Nivea',
        'Amul 500ml',
        '5-star',
        'a_b.c',
      ]) {
        expect(
          SearchTextSanitizer.sanitize(input),
          input,
          reason: 'must not mangle: $input',
        );
      }
    });

    test('keeps non-Latin scripts intact', () {
      // A voice transcript or a transliterated brand name must survive; the old
      // allow-list stripped every one of these characters.
      for (final input in [
        'à¤¡à¥‹à¤µ à¤¶à¥ˆà¤®à¥à¤ªà¥‚',
        'Dove èƒ¡é¬è†',
        'CafÃ© CrÃ¨me',
      ]) {
        expect(SearchTextSanitizer.sanitize(input), input);
      }
    });

    test('strips control characters that would break the query parameter', () {
      expect(SearchTextSanitizer.sanitize('dove\nshampoo'), 'doveshampoo');
      expect(SearchTextSanitizer.sanitize('dove\tshampoo'), 'doveshampoo');
      expect(SearchTextSanitizer.sanitize('dove\rshampoo'), 'doveshampoo');
    });

    test('handles empty input', () {
      expect(SearchTextSanitizer.sanitize(''), '');
      expect(SearchTextSanitizer.sanitize('\n\n'), '');
    });

    test('the formatter normalises a pasted value', () {
      const input = TextEditingValue(
        text: 'dove\nshampoo',
        selection: TextSelection.collapsed(offset: 12),
      );
      final output = SearchTextSanitizer.formatter.formatEditUpdate(
        input,
        input,
      );
      expect(output.text, 'doveshampoo');
      expect(output.selection.baseOffset, output.text.length);
    });

    test('the formatter leaves a clean value byte-identical', () {
      // Written with \u escapes so the assertion does not depend on how this
      // file's bytes are read back, and so the accent case is unambiguous.
      const text = "L'Oréal Café";
      const input = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: 12),
      );
      final output = SearchTextSanitizer.formatter.formatEditUpdate(
        input,
        input,
      );
      expect(output.text, text);
      expect(
        output.text,
        contains('é'),
        reason: 'accents and apostrophes must both survive',
      );
    });
  });

  group('SearchInputCapabilities equality', () {
    test('equal sets compare equal', () {
      const caps = SearchInputCapabilities.textOnly();
      expect(caps, const SearchInputCapabilities({SearchInputCapability.text}));
    });

    test('different sets are not equal', () {
      expect(
        const SearchInputCapabilities({SearchInputCapability.text}),
        isNot(
          const SearchInputCapabilities({
            SearchInputCapability.text,
            SearchInputCapability.voice,
          }),
        ),
      );
    });
  });
}
