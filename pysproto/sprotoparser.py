# -*- coding: utf-8 -*-
from __future__ import unicode_literals, print_function
from pypeg2 import * 

pypeg2_parse = parse #rename it,for avoiding name conflict
tag = re.compile(r"\d+")
nomeaning = blank, maybe_some(comment_sh), blank
fullname = optional(word, "."), word

class MainKey(str):
    grammar = "(", word, ")"

class TypeName(object):
    grammar = flag("is_arr", "*"), attr("fullname", fullname)

class Filed(List):
    grammar = attr("filed", word), attr("tag", tag), ":", attr("typename", TypeName),\
            optional(MainKey), nomeaning, endl

class Struct(List):pass
class Type(List):pass

Struct.grammar = "{", nomeaning, attr("fileds", maybe_some([Filed, Type])), "}"
Type.grammar = nomeaning, ".", name(), attr("struct", Struct), nomeaning

class Sub_pro_type(Keyword):
    grammar = Enum(K("request"), K("response"))

class Subprotocol(List):
    grammar = attr("subpro_type", Sub_pro_type), attr("pro_filed", [TypeName, Struct]), nomeaning

class Protocol(List):
    grammar = nomeaning, attr("name", word), attr("tag",tag), "{", nomeaning, attr("fileds", maybe_some(Subprotocol)), "}", nomeaning

class Sproto(List):
    grammar = attr("items", maybe_some([Type, Protocol]))
#====================================================================

_builtin_types = ["string", "integer", "boolean"]

class Convert:
    group = {}
    type_dict = {}
    protocol_dict = {}
    protocol_tags = {} #just for easiliy check

    @staticmethod
    def parse(text, name):
        Convert.group = {}
        Convert.type_dict = {}
        Convert.protocol_dict = {}
        Convert.protocol_tags = {}

        obj = pypeg2_parse(text, Sproto)
        for i in obj.items:
            if hasattr(i,"tag"):
                Convert.convert_protocol(i)
            else:
                Convert.convert_type(i)

        Convert.group["type"] = Convert.type_dict
        Convert.group["protocol"] = Convert.protocol_dict
        return Convert.group
    @staticmethod
    def convert_type(obj, parent_name = ""):
        if parent_name != "":
            obj.name = parent_name + "." + obj.name
        type_name = obj.name
        if type_name in Convert.type_dict.keys():
            print("Error:redifine %s\n" % (type_name))
            return False
        Convert.type_dict[type_name] = Convert.convert_struct(obj.struct, type_name)

    @staticmethod
    def convert_struct(obj, name = ""):
        struct = []
        for filed in obj.fileds:
            if type(filed) == Filed:
                filed_typename = '.'.join(filed.typename.fullname)
                filed_type = Convert.get_typename(filed_typename)
                #if not ok:
                #    print("Error: Undefined type %s in type %s at %s.sproto" % (filed_typename, name, Convert.namespace))
                #    sys.exit()
                filed_info = {}
                filed_info["name"] = filed.filed
                filed_info["tag"] = filed.tag
                filed_info["array"] = filed.typename.is_arr
                filed_info["typename"] = filed_typename
                filed_info["type"] = filed_type
                struct.append(filed_info)
            elif type(filed) == Type:
                Convert.convert_type(filed, name) 
        return struct

    @staticmethod
    def convert_protocol(obj):
        if obj.name in Convert.protocol_dict.keys():
            print("Error:redifine protocol %s \n" % (obj.name))
            return
        if obj.tag in Convert.protocol_tags.keys():
            print("Error:redifine protocol tags %d \n" % (obj.tag))
            return
        protocol = {}
        protocol["tag"] = obj.tag
        for fi in obj.fileds:
            #if type(fi.pro_filed) == TypeName:
                #ok = Convert.check_type_exists(fi.pro_filed.fullname)
                #if not ok:
                #    protocol[fi.subpro_type] = fi.pro_filed.name
                #else:
                #    print("Error:non define typename %s \n" % (fi.pro_filed))
                #    return
            if type(fi.pro_filed) == Struct:
                newtype_name = obj.name + "." + fi.subpro_type
                Convert.type_dict[newtype_name] = Convert.convert_struct(fi.pro_filed, newtype_name)
                protocol[fi.subpro_type] = newtype_name
           
        Convert.protocol_dict[obj.name] = protocol
        Convert.protocol_tags[obj.tag] = obj.tag

    @staticmethod
    def get_typename(name):
        if name in _builtin_types:
            return "builtin"
        else:
            return "UserDefine"

def dump():
    print("to do dump")
    pass

__all__ = ["parse"]
def parse(text, name="=text"):
    result = Convert.parse(text, name) 
    return result

