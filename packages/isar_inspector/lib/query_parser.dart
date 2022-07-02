// ignore_for_file: cast_nullable_to_non_nullable

import 'package:dartx/dartx.dart';
import 'package:isar/isar.dart';
import 'package:isar_inspector/schema.dart';
import 'package:petitparser/petitparser.dart';

class QueryParser {
  QueryParser(this.properties) {
    final builder = ExpressionBuilder();
    builder.group().primitive(QueryGrammar.condition,
        (List<dynamic> condition) {
      final property = condition[0] as String;
      final cmp = condition[1] as String;
      final value = condition[2];
      return createQueryCondition(property, cmp, value);
    });

    builder.group().wrapper(
          char('(').trim(),
          char(')').trim(),
          (Object? left, Object? value, Object? right) => value,
        );

    builder.group().left(
          string('&&').trim(),
          (Object? l, _, Object? r) => FilterGroup.and(
            [l as FilterOperation, r as FilterOperation],
          ),
        );

    builder.group().left(
          string('||').trim(),
          (Object? l, _, Object? r) => FilterGroup.or(
            [l as FilterOperation, r as FilterOperation],
          ),
        );

    builder.group().left(
      string('^').trim(),
          (Object? l, _, Object? r) => FilterGroup.xor(
        [l as FilterOperation, r as FilterOperation],
      ),
    );

    _parser = builder.build();
  }
  final List<IProperty> properties;
  late final Parser _parser;

  FilterOperation createQueryCondition(
    String propertyName,
    String cmp,
    dynamic value,
  ) {
    final property =
        properties.where((IProperty p) => p.name == propertyName).firstOrNull;

    if (property == null) {
      throw IsarError('Unknown property "$propertyName"');
    }

    switch (cmp) {
      case '!=':
      case '==':
        final filter = FilterCondition.equalTo(
          property: propertyName,
          value: value,
        );
        if (cmp == '!=') {
          return FilterGroup.not(filter);
        } else {
          return filter;
        }
      case '>':
      case '>=':
        return FilterCondition.greaterThan(
          property: propertyName,
          value: value,
          include: cmp == '>=',
        );
      case '<':
      case '<=':
        return FilterCondition.lessThan(
          property: propertyName,
          value: value,
          include: cmp == '<=',
        );
      case 'matches':
        return FilterCondition.matches(
          property: propertyName,
          wildcard: value as String,
        );
      default:
        throw UnimplementedError();
    }
  }

  FilterOperation parse(String filter) {
    final result = _parser.parse(filter);
    if (result.isFailure) {
      throw IsarError(result.message);
    }
    return result.value as FilterOperation;
  }
}

// ignore: avoid_classes_with_only_static_members
class QueryGrammar {
  static Parser get cmpOperator =>
      string('==') |
      string('!=') |
      string('>') |
      string('>=') |
      string('<') |
      string('<=') |
      'matches'.toParser(caseInsensitive: true).map((_) => 'matches');

  static Parser get boolToken =>
      (string('true') | string('false')).map((value) => value == 'true');

  static Parser<num> get numberToken => ((digit() | char('.')).and() &
          (digit().star() &
              ((char('.') & digit().plus()) |
                      (char('x') & digit().plus()) |
                      (anyOf('Ee') & anyOf('+-').optional() & digit().plus()))
                  .optional()))
      .flatten()
      .map(num.parse);

  static String unescape(String v) => v.replaceAllMapped(
        RegExp("\\\\[nrtbf\"']"),
        (Match v) => const {
          'n': '\n',
          'r': '\r',
          't': '\t',
          'b': '\b',
          'f': '\f',
          'v': '\v',
          "'": "'",
          '"': '"'
        }[v.group(0)!.substring(1)]!,
      );

  static Parser<String> get escapedChar =>
      (char(r'\') & anyOf("nrtbfv\"'")).pick(1).cast();

  static Parser<String> get sqStringToken => (char("'") &
          (anyOf(r"'\").neg() | escapedChar).star().flatten() &
          char("'"))
      .pick(1)
      .map((v) => unescape(v as String));

  static Parser<String> get dqStringToke => (char('"') &
          (anyOf(r'"\').neg() | escapedChar).star().flatten() &
          char('"'))
      .pick(1)
      .map((v) => unescape(v as String));

  static Parser<String> get stringToken =>
      sqStringToken.or(dqStringToke).cast();

  static Parser get valueToken => boolToken | numberToken | stringToken;

  static Parser get identifier =>
      (letter() | digit()).plus().map((List<dynamic> chars) => chars.join());

  static Parser<List<dynamic>> get condition =>
      identifier.trim() & cmpOperator.trim() & valueToken.trim();
}
