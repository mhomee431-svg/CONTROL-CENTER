/// GSTIN decoder — extracts owner/state details from a 15-character GSTIN so
/// the shop registration form can "confirm the shop owner".
///
/// GSTIN format: `{state(2)}{PAN(10)}{entity(1)}{Z(1)}{check(1)}`
///   22 AAAAA0000A 1 Z 5
///   │  └─ PAN of the business/owner ─┘ │ │ └─ check digit
///   └─ state code                     │ └─ 'Z' (default)
///                                    └─ entity type
class GstinDetails {
  const GstinDetails({
    required this.isValid,
    this.stateCode,
    this.stateName,
    this.pan,
    this.entityCode,
    this.entityName,
  });

  final bool isValid;
  final String? stateCode;
  final String? stateName;
  final String? pan;
  final String? entityCode;
  final String? entityName;
}

/// Official GST state codes (01–38).
const Map<String, String> kGstStateCodes = {
  '01': 'Jammu & Kashmir',
  '02': 'Himachal Pradesh',
  '03': 'Punjab',
  '04': 'Chandigarh',
  '05': 'Uttarakhand',
  '06': 'Haryana',
  '07': 'Delhi',
  '08': 'Rajasthan',
  '09': 'Uttar Pradesh',
  '10': 'Bihar',
  '11': 'Sikkim',
  '12': 'Arunachal Pradesh',
  '13': 'Nagaland',
  '14': 'Manipur',
  '15': 'Mizoram',
  '16': 'Tripura',
  '17': 'Meghalaya',
  '18': 'Assam',
  '19': 'West Bengal',
  '20': 'Jharkhand',
  '21': 'Odisha',
  '22': 'Chhattisgarh',
  '23': 'Madhya Pradesh',
  '24': 'Gujarat',
  '26': 'Dadra & Nagar Haveli and Daman & Diu',
  '27': 'Maharashtra',
  '28': 'Karnataka',
  '29': 'Telangana',
  '30': 'Andhra Pradesh',
  '31': 'Goa',
  '32': 'Lakshadweep',
  '33': 'Kerala',
  '34': 'Tamil Nadu',
  '35': 'Puducherry',
  '36': 'Andaman & Nicobar Islands',
  '37': 'Telangana',
  '38': 'Ladakh',
};

/// GST entity-type codes (13th character).
const Map<String, String> kGstEntityCodes = {
  '1': 'Registered Person',
  '2': 'Composition Taxable Person',
  '3': 'Casual Taxable Person',
  '4': 'SEZ Unit',
  '5': 'Non-Resident Taxable Person',
  '6': 'SEZ Developer',
  '7': 'UN Agencies',
};

class GstinDecoder {
  GstinDecoder._();
  static final GstinDecoder instance = GstinDecoder._();

  /// Decode a GSTIN. Returns [GstinDetails.isValid] = false for invalid input.
  GstinDetails decode(String raw) {
    final gstin = raw.trim().toUpperCase();
    if (!RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$')
        .hasMatch(gstin)) {
      return const GstinDetails(isValid: false);
    }

    final stateCode = gstin.substring(0, 2);
    final pan = gstin.substring(2, 12);
    final entityCode = gstin[12];
    return GstinDetails(
      isValid: true,
      stateCode: stateCode,
      stateName: kGstStateCodes[stateCode],
      pan: pan,
      entityCode: entityCode,
      entityName: kGstEntityCodes[entityCode],
    );
  }
}