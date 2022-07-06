import 'package:json_ast/json_ast.dart' show Node;

import 'helpers.dart';

const String emptyListWarn = "list is empty";
const String ambiguousListWarn = "list is ambiguous";
const String ambiguousTypeWarn = "type is ambiguous";

class Warning {
  final String warning;
  final String path;

  Warning(this.warning, this.path);
}

Warning newEmptyListWarn(String path) => Warning(emptyListWarn, path);

Warning newAmbiguousListWarn(String path) => Warning(ambiguousListWarn, path);

Warning newAmbiguousType(String path) => Warning(ambiguousTypeWarn, path);

class WithWarning<T> {
  final T result;
  final List<Warning> warnings;

  WithWarning(this.result, this.warnings);
}

class TypeDefinition {
  String name;
  String? subtype;
  bool isAmbiguous = false;
  bool _isPrimitive = false;

  factory TypeDefinition.fromDynamic(dynamic obj, Node? astNode) {
    bool isAmbiguous = false;
    final type = getTypeName(obj);
    if (type == 'List') {
      List<dynamic> list = obj;
      String elemType;
      if (list.length > 0) {
        elemType = getTypeName(list[0]);
        for (dynamic listVal in list) {
          final typeName = getTypeName(listVal);
          if (elemType != typeName) {
            isAmbiguous = true;
            break;
          }
        }
      } else {
        // when array is empty insert Null just to warn the user
        elemType = "Null";
      }
      return TypeDefinition(type,
          astNode: astNode, subtype: elemType, isAmbiguous: isAmbiguous);
    }
    return TypeDefinition(type, astNode: astNode, isAmbiguous: isAmbiguous);
  }

  TypeDefinition(
    this.name, {
    this.subtype,
    this.isAmbiguous = false,
    Node? astNode,
  }) {
    if (subtype == null) {
      _isPrimitive = isPrimitiveType(this.name);
      if (this.name == 'int' && isASTLiteralDouble(astNode)) {
        this.name = 'double';
      }
    } else {
      _isPrimitive = isPrimitiveType('$name<$subtype>');
    }
  }

  bool operator ==(other) {
    if (other is TypeDefinition) {
      TypeDefinition otherTypeDef = other;
      return this.name == otherTypeDef.name &&
          this.subtype == otherTypeDef.subtype &&
          this.isAmbiguous == otherTypeDef.isAmbiguous &&
          this._isPrimitive == otherTypeDef._isPrimitive;
    }
    return false;
  }

  bool get isPrimitive => _isPrimitive;

  bool get isPrimitiveList => _isPrimitive && name == 'List';

  String _buildParseClass(String expression) {
    final properType = subtype != null ? subtype : name;
    return '$properType.fromJson($expression)';
  }

  String _buildToJsonClass(String expression,
      [bool propertiesOptional = true]) {
    if (propertiesOptional) {
      return '$expression?.toJson()';
    }
    return '$expression.toJson()';
  }

  String jsonParseExpression(
      String key, bool privateField, bool propertiesOptional) {
    // final jsonKey = "json['$key']";
    // final fieldKey =
    //     fixFieldName(key, typeDef: this, privateField: privateField);
    // if (isPrimitive) {
    //   if (name == "List") {
    //     return "$fieldKey = json['$key'].cast<$subtype>();";
    //   }
    //   return "$fieldKey = json['$key'];";
    // } else if (name == "List" && subtype == "DateTime") {
    //   return "$fieldKey = json['$key'].map((v) => DateTime.tryParse(v));";
    // } else if (name == "DateTime") {
    //   return "$fieldKey = DateTime.tryParse(json['$key']);";
    // } else if (name == 'List') {
    //   // list of class
    //   return "if (json['$key'] != null) {\n\t\t\t$fieldKey = <$subtype>[];\n\t\t\tjson['$key'].forEach((v) { $fieldKey!.add(new $subtype.fromJson(v)); });\n\t\t}";
    // } else {
    //   // class
    //   return "$fieldKey = json['$key'] != null ? ${_buildParseClass(jsonKey)} : null;";
    // }

    // Modified:
    final jsonKey = "json['$key']";
    final fieldKey =
        fixFieldName(key, typeDef: this, privateField: privateField);
    if (isPrimitive) {
      if (name == "List") {
        return propertiesOptional
            ? "$fieldKey: json['$key']?.cast<$subtype>(),"
            : "$fieldKey: json['$key'].cast<$subtype>(),";
      }
      return "$fieldKey: json['$key'],";
    } else if (name == "List" && subtype == "DateTime") {
      return propertiesOptional
          ? "$fieldKey: json['$key']?.map((v) => DateTime.tryParse(v)),"
          : "$fieldKey: json['$key'].map((v) => DateTime.tryParse(v)),";
    } else if (name == "DateTime") {
      return "$fieldKey: DateTime.tryParse(json['$key']),";
    } else if (name == 'List') {
      // list of class
      // return "$fieldKey: $jsonKey == null ? null : List<${fixNamePlural(subtype ?? 'dynamic')}>.from($jsonKey.map((v) => ${fixNamePlural(subtype ?? 'dynamic')}.fromJson(v))),";
      return propertiesOptional
          ? "$fieldKey: $jsonKey == null ? null : List<${fixNamePlural(subtype ?? 'dynamic')}>.from($jsonKey.map((v) => ${fixNamePlural(subtype ?? 'dynamic')}.fromJson(v))),"
          : "$fieldKey: List<${fixNamePlural(subtype ?? 'dynamic')}>.from($jsonKey.map((v) => ${fixNamePlural(subtype ?? 'dynamic')}.fromJson(v))),";
    } else {
      // class
      // return "$fieldKey: $jsonKey == null ? null : ${_buildParseClass(jsonKey)},";
      return propertiesOptional
          ? "$fieldKey: $jsonKey == null ? null : ${_buildParseClass(jsonKey)},"
          : "$fieldKey: ${_buildParseClass(jsonKey)},";
    }
  }

  String toJsonExpression(
    String key,
    bool privateField,
    bool propertiesOptional, [
    bool copyingWith = false,
  ]) {
    // final fieldKey =
    //     fixFieldName(key, typeDef: this, privateField: privateField);
    // final thisKey = 'this.$fieldKey';
    // if (isPrimitive) {
    //   return "data['$key'] = $thisKey;";
    // } else if (name == 'List') {
    //   // class list
    //   return """if ($thisKey != null) {
    //   data['$key'] = $thisKey!.map((v) => ${_buildToJsonClass('v', false)}).toList();
    // }""";
    // } else {
    //   // class
    //   return """if ($thisKey != null) {
    //   data['$key'] = ${_buildToJsonClass(thisKey)};
    // }""";
    // }

    // Modified:
    final fieldKey =
        fixFieldName(key, typeDef: this, privateField: privateField);
    final thisKey = '$fieldKey';
    if (isPrimitive) {
      return "'$key': $thisKey,";
    } else if (name == 'List') {
      return "'$key': $thisKey${propertiesOptional ? '?' : ''}.map((v) => ${_buildToJsonClass('v', false)}).toList(),";
    } else {
      // class
      return "'$key': ${_buildToJsonClass(thisKey, propertiesOptional)},";
    }
  }

  String toJsonExpressionCopyWith(
    String key,
    TypeDefinition f,
    bool propertyOptional,
  ) {
    final fieldFix = "${fixFieldName(key, typeDef: f, privateField: false)}";
    return "$fieldFix: $fieldFix ?? this.$fieldFix,";

    /*final fieldKey = fixFieldName(key, typeDef: this, privateField: false);
    final thisKey = '$fieldKey';
    if (isPrimitive) {
      return "$key: $key${propertyOptional ? '?? this.$key' : ''},";
    } else if (name == 'List') {
      return "'$key': $thisKey?.map((v) => ${_buildToJsonClass('v', false)}).toList(),";
    } else {
      // class
      return "'$key': ${_buildToJsonClass(thisKey)},";
    }*/
  }
}

class Dependency {
  String name;
  final TypeDefinition typeDef;

  Dependency(this.name, this.typeDef);

  String get className => camelCase(name);
}

class ClassDefinition {
  final String _name;
  final bool privateFields;

  // Modified.
  final bool propertiesFinal;
  final bool propertiesOptional;
  final bool addCopyWith;
  final bool addToString;
  final bool addEquatable;

  final Map<String, TypeDefinition> fields = Map<String, TypeDefinition>();

  ClassDefinition(
    this._name, {
    this.privateFields = false,
    this.propertiesFinal = true,
    this.propertiesOptional = true,
    this.addCopyWith = false,
    this.addToString = true,
    this.addEquatable = false,
  });

  String get name {
    // return _name;

    // Modified:
    return fixNamePlural(_name);
  }

  List<Dependency> get dependencies {
    final dependenciesList = <Dependency>[];
    final keys = fields.keys;
    keys.forEach((k) {
      final f = fields[k];
      if (f != null && !f.isPrimitive) {
        dependenciesList.add(Dependency(k, f));
      }
    });
    return dependenciesList;
  }

  bool operator ==(other) {
    if (other is ClassDefinition) {
      ClassDefinition otherClassDef = other;
      return this.isSubsetOf(otherClassDef) && otherClassDef.isSubsetOf(this);
    }
    return false;
  }

  bool isSubsetOf(ClassDefinition other) {
    final List<String> keys = this.fields.keys.toList();
    final int len = keys.length;
    for (int i = 0; i < len; i++) {
      TypeDefinition? otherTypeDef = other.fields[keys[i]];
      if (otherTypeDef != null) {
        TypeDefinition? typeDef = this.fields[keys[i]];
        if (typeDef != otherTypeDef) {
          return false;
        }
      } else {
        return false;
      }
    }
    return true;
  }

  hasField(TypeDefinition otherField) {
    final key = fields.keys
        .firstWhere((k) => fields[k] == otherField, orElse: () => "");
    return key != "";
  }

  addField(String name, TypeDefinition typeDef) {
    fields[name] = typeDef;
  }

  void _addTypeDef(TypeDefinition typeDef, StringBuffer sb,
      [bool isCopyingWith = false]) {
    sb.write(
        '${!isCopyingWith && propertiesFinal ? 'final' : ''} ${fixNamePlural(typeDef.name)}');
    if (typeDef.subtype != null) {
      sb.write('<${fixNamePlural(typeDef.subtype!)}>');
    }
  }

  String get _equatableImprt {
    final sb = StringBuffer();
    if (addEquatable) {
      sb.write("import 'package:equatable/equatable.dart';");
      sb.write('\n\n');
    }
    return sb.toString();
  }

  String get _equatableExt {
    final sb = StringBuffer();
    if (addEquatable) {
      sb.write("extends Equatable ");
    }
    return sb.toString();
  }

  String get _fieldList {
    return fields.keys.map((key) {
      final f = fields[key]!;
      final fieldName =
          fixFieldName(key, typeDef: f, privateField: privateFields);
      final sb = StringBuffer();
      sb.write('\t');
      _addTypeDef(f, sb);
      sb.write('${propertiesOptional ? '?' : ''} $fieldName;');
      return sb.toString();
    }).join('\n');
  }

  // String get _gettersSetters {
  //   return fields.keys.map((key) {
  //     final f = fields[key]!;
  //     final publicFieldName =
  //         fixFieldName(key, typeDef: f, privateField: false);
  //     final privateFieldName =
  //         fixFieldName(key, typeDef: f, privateField: true);
  //     final sb = StringBuffer();
  //     sb.write('\t');
  //     _addTypeDef(f, sb);
  //     sb.write(
  //         '? get $publicFieldName => $privateFieldName;\n\tset $publicFieldName(');
  //     _addTypeDef(f, sb);
  //     sb.write('? $publicFieldName) => $privateFieldName = $publicFieldName;');
  //     return sb.toString();
  //   }).join('\n');
  // }

  // String get _defaultPrivateConstructor {
  //   final sb = StringBuffer();
  //   sb.write('\t$name({');
  //   var i = 0;
  //   var len = fields.keys.length - 1;
  //   fields.keys.forEach((key) {
  //     final f = fields[key]!;
  //     final publicFieldName =
  //         fixFieldName(key, typeDef: f, privateField: false);
  //     _addTypeDef(f, sb);
  //     sb.write('? $publicFieldName');
  //     if (i != len) {
  //       sb.write(', ');
  //     }
  //     i++;
  //   });
  //   sb.write('}) {\n');
  //   fields.keys.forEach((key) {
  //     final f = fields[key]!;
  //     final publicFieldName =
  //         fixFieldName(key, typeDef: f, privateField: false);
  //     final privateFieldName =
  //         fixFieldName(key, typeDef: f, privateField: true);
  //     sb.write('if ($publicFieldName != null) {\n');
  //     sb.write('this.$privateFieldName = $publicFieldName;\n');
  //     sb.write('}\n');
  //   });
  //   sb.write('}');
  //   return sb.toString();
  // }

  String get _defaultConstructor {
    final sb = StringBuffer();
    sb.write('\t${fixNamePlural(name)}({');
    var i = 0;
    var len = fields.keys.length - 1;
    fields.keys.forEach((key) {
      final f = fields[key]!;
      final fieldName =
          fixFieldName(key, typeDef: f, privateField: privateFields);
      sb.write('${propertiesOptional ? '' : 'required'} this.$fieldName');
      if (i != len) {
        sb.write(', ');
      }
      i++;
    });
    sb.write(',});');
    return sb.toString();
  }

  String get _copyWithFunc {
    final sb = StringBuffer();
    if (addCopyWith) {
      sb.write('\t${fixNamePlural(name)} copyWith({\n');
      for (var k in fields.keys) {
        final f = fields[k]!;
        final fieldName =
            fixFieldName(k, typeDef: f, privateField: privateFields);
        sb.write('\t');
        _addTypeDef(f, sb, true);
        // sb.write('${propertiesOptional ? '?' : ''} $fieldName,');
        sb.write('? $fieldName,');
      }
      sb.write('}) =>\n\t\t$name(\n');
      fields.keys.forEach((k) {
        final f = fields[k]!;
        sb.write(
            '\t\t\t${fields[k]!.toJsonExpressionCopyWith(k, f, propertiesOptional)}\n');
      });
      sb.write('\t);');

      sb.write('\n\n');
    }
    return sb.toString();
  }

  String get _jsonParseFunc {
    // final sb = new StringBuffer();
    // sb.write('\t$name');
    // sb.write('.fromJson(Map<String, dynamic> json) {\n');
    // fields.keys.forEach((k) {
    //   sb.write('\t\t${fields[k]!.jsonParseExpression(k, privateFields)}\n');
    // });
    // sb.write('\t}');
    // return sb.toString();

    // Modified:
    final sb = StringBuffer();
    sb.write('\tfactory $name');
    sb.write('.fromJson(Map<String, dynamic> json) => $name(\n');
    fields.keys.forEach((k) {
      sb.write(
          '\t\t${fields[k]!.jsonParseExpression(k, privateFields, propertiesOptional)}\n');
    });
    sb.write('\t);');
    return sb.toString();
  }

  String get _jsonGenFunc {
    // final sb = new StringBuffer();
    // sb.write(
    //     '\tMap<String, dynamic> toJson() {\n\t\tfinal Map<String, dynamic> data = new Map<String, dynamic>();\n');
    // fields.keys.forEach((k) {
    //   sb.write('\t\t${fields[k]!.toJsonExpression(k, privateFields)}\n');
    // });
    // sb.write('\t\treturn data;\n');
    // sb.write('\t}');
    // return sb.toString();

    // Modified:
    final sb = StringBuffer();
    sb.write('\tMap<String, dynamic> toJson() => {\n');
    fields.keys.forEach((k) {
      sb.write(
          '\t\t${fields[k]!.toJsonExpression(k, privateFields, propertiesOptional)}\n');
    });
    sb.write('\t};');
    return sb.toString();
  }

  String get _toStringFunc {
    final sb = StringBuffer();
    if (addToString) {
      sb.write("\n\t@override\n\tString toString() => '\${toJson()}';");
    }
    return sb.toString();
  }

  String get _equatableOvrr {
    final sb = StringBuffer();
    if (addEquatable) {
      sb.write(
          "\n\t@override\n\t// TODO: implement\n\tList<Object> get props => throw UnimplementedError();\n");
    }
    return sb.toString();
  }

  String toString() {
    return 'class $name $_equatableExt{\n$_fieldList\n\n$_defaultConstructor\n\n$_copyWithFunc$_jsonParseFunc\n\n$_jsonGenFunc\n$_toStringFunc\n$_equatableOvrr}\n';
    // if (privateFields) {
    //   return 'class $name {\n$_fieldList\n\n$_defaultPrivateConstructor\n\n$_gettersSetters\n\n$_jsonParseFunc\n\n$_jsonGenFunc\n}\n';
    // } else {
    //   return 'class $name {\n$_fieldList\n\n$_defaultConstructor\n\n$_jsonParseFunc\n\n$_jsonGenFunc\n}\n';
    // }
  }
}
