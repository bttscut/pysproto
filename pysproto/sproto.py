from . import core

__all__ = ["SprotoRpc"]

class Sproto(object):
    def __init__(self, chunk):
        self.sp = core.newproto(chunk)
        self.st = {}
        self.proto = {}

    def querytype(self, tagname):
        if not tagname in self.st:
            self.st[tagname] = core.query_type(self.sp, tagname)
        return self.st[tagname]

    def protocol(self, protoname):
        # print "protocol", protoname
        if not protoname in self.proto:
            self.proto[protoname] = core.protocol(self.sp, protoname)
        return self.proto[protoname]

    def encode(self, st, data):
        # print "encode", data
        if isinstance(st, basestring):
            st = self.querytype(st)
        return core.encode(st, data)

    def decode(self, st, chunk):
        # print "decode"
        if isinstance(st, basestring):
            st = self.querytype(st)
        return core.decode(st, chunk)

    def pack(self, chunk):
        return core.pack(chunk)

    def unpack(self, chunk):
        return core.unpack(chunk)

class SprotoRpc(object):
    def __init__(self, c2s_chunk, s2c_chunk, packagename):
        self._c2s = Sproto(c2s_chunk)
        self._s2c = Sproto(s2c_chunk)
        self._package = packagename
        self._session = {}

    def dispatch(self, data):
        sp = self._s2c
        data = sp.unpack(data)
        header,size = sp.decode(self._package, data)
        content = data[size:]
        if header.get("type", 0):
            # request
            protoname, req, resp = sp.protocol(header["type"])
            result,_ = sp.decode(req, content) if req else None
            ret = {"type":"REQUEST", "proto": protoname, "msg":result, "session":None}
            if header.get("session", 0):
                ret["session"] = header["session"]
        else:
            # response
            session = header["session"]
            if not session in self._session:
                raise ValueError("unknown session", session)
            response = self._session[session]
            del self._session[session]
            ret = {"type":"RESPONSE", "session":session, "msg":None}

            if response != True:
                ret["msg"], _ = sp.decode(response, content)
        ret["header"] = header
        return ret
            
    def request(self, protoname, args = None, session = 0):
        sp = self._c2s
        tag, req, resp = sp.protocol(protoname)
        header = sp.encode(self._package, {"type":tag, "session":session})
        if session and not resp:
            raise ValueError("proto no response")
        if session:
            self._session[session] = resp or True
        content = sp.encode(req, args) if args else ""
        return sp.pack(header + content)

    def response(self, protoname, args, session):
        sp = self._s2c
        tag, _, resp = sp.protocol(protoname)
        header = sp.encode(self._package, {"session":session})
        content = sp.encode(resp, args) if args else ""
        return sp.pack(header + content)
