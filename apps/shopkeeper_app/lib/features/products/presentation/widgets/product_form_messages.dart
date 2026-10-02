import 'package:flutter/widgets.dart';

import '../../../../core/l10n/app_text.dart';
import '../../domain/product_form_rules.dart';

/// The wording for a broken product-form rule, in the active locale.
///
/// The domain layer says WHICH rule broke ([ProductFormFieldFailure]); this is
/// where that becomes a sentence, because the sentence is UI copy and lives in
/// `app_en.arb`. Flutter's `FormField.validator` contract is `String?`, so the
/// sheets wrap their validators with this function.
String? productFormErrorText(
    BuildContext context, ProductFormFieldFailure? failure) {
  if (failure == null) return null;
  final text = appText(context);
  return switch (failure.code) {
    ProductFormFieldError.nameRequired => text.formProductNameRequired,
    ProductFormFieldError.priceRequired => text.formSellingPriceRequired,
    ProductFormFieldError.invalidAmount => text.formEnterValidAmount,
    ProductFormFieldError.priceNegative => text.formPriceCannotBeNegative,
    ProductFormFieldError.mrpNegative => text.formMrpCannotBeNegative,
    ProductFormFieldError.mrpBelowPrice => text.formMrpBelowPrice,
    ProductFormFieldError.wholeNumberRequired => text.formWholeNumberRequired,
    ProductFormFieldError.quantityNegative => text.formQuantityCannotBeNegative,
    ProductFormFieldError.barcodeTooShort => text.formBarcodeTooShort(
        failure.count ?? ProductFormRules.barcodeMinLength),
    ProductFormFieldError.tooManyCharacters =>
      text.formTooManyCharacters(failure.count ?? 0),
  };
}
