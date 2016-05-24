cdef extern from "sproto.h":
    enum: SPROTO_REQUEST
    enum: SPROTO_RESPONSE
    enum: SPROTO_TINTEGER
    enum: SPROTO_TBOOLEAN
    enum: SPROTO_TSTRING
    enum: SPROTO_TSTRUCT
    enum: SPROTO_CB_ERROR
    enum: SPROTO_CB_NIL
    enum: SPROTO_CB_NOARRAY

    struct sproto:
        pass
    struct sproto_type:
        pass
    struct sproto_arg:
        void *ud
        const char *tagname
        int tagid
        int type
        sproto_type *subtype
        void *value
        int length
        int index
        int mainindex

    sproto* sproto_create(void *, size_t)
    void sproto_release(sproto*)
    sproto_type* spt "sproto_type"(sproto*, char*)
    int sproto_pack(void*, int, void*, int)
    int sproto_unpack(void*, int, void*, int)
    int sproto_prototag(const sproto *, const char * name)
    const char * sproto_protoname(const sproto *, int proto)
    sproto_type * sproto_protoquery(const sproto *, int proto, int what)
    void sproto_dump(sproto*)
    ctypedef int (*sproto_callback)(const sproto_arg *args) except SPROTO_CB_ERROR
    int sproto_encode(const sproto_type *, void * buffer, int size, sproto_callback cb, void *ud)
    int sproto_decode(const sproto_type *, const void * data, int size, sproto_callback cb, void *ud)

from cpython.pycapsule cimport *
from libc.stdint cimport *
from libc.stdio cimport printf
from libc.string cimport memcpy
from cpython.mem cimport PyMem_Malloc, PyMem_Free, PyMem_Realloc
from cpython.object cimport PyObject

cdef enum:
    prealloc = 2050
    max_deeplevel = 64

cdef struct encode_ud:
    PyObject *data
    int deep

cdef int _encode(const sproto_arg *args) except SPROTO_CB_ERROR:
    cdef encode_ud *self = <encode_ud*>args.ud
    # todo check deep
    data = <object>self.data
    obj = None
    tn = args.tagname
    if args.index > 0:
        if tn not in data:
            return SPROTO_CB_NOARRAY
        try:
            obj = data[args.tagname][args.index-1]
        except IndexError:
            return SPROTO_CB_NIL
    else:
        if tn not in data:
            return SPROTO_CB_NIL
        obj = data[tn]
    cdef int64_t v, vh
    cdef char* ptr
    cdef encode_ud *sub
    if args.type == SPROTO_TINTEGER:
        v = obj
        vh = v >> 31
        if vh == 0 or vh == -1:
            (<int32_t *>args.value)[0] = <int32_t>v;
            return 4
        else:
            (<int64_t *>args.value)[0] = <int64_t>v;
            return 8
    elif args.type == SPROTO_TBOOLEAN:
        v = obj
        (<int *>args.value)[0] = <int>v
        return 4
    elif args.type == SPROTO_TSTRING:
        ptr = obj
        v = len(obj)
        if v > args.length:
            return SPROTO_CB_ERROR
        memcpy(args.value, ptr, <size_t>v)
        return v
    elif args.type == SPROTO_TSTRUCT:
        sub = <encode_ud *>PyMem_Malloc(sizeof(encode_ud))
        try:
            sub.data = <PyObject *>obj
            sub.deep = self.deep + 1
            r = sproto_encode(args.subtype, args.value, args.length, _encode, sub)
            if r < 0:
                return SPROTO_CB_ERROR
            return r
        finally:
            PyMem_Free(sub)
    raise Exception("Invalid field type %d"%args.type)
    return -1

cdef del_sproto(object obj):
    sp = <sproto*>PyCapsule_GetPointer(obj, NULL)
    sproto_release(sp)

def encode(stobj, data):
    assert isinstance(data, dict)
    cdef encode_ud self
    cdef sproto_type *st = <sproto_type*>PyCapsule_GetPointer(stobj, NULL)
    cdef char* buf = <char*>PyMem_Malloc(prealloc)
    cdef int sz = prealloc
    try:
        while 1:
            self.data = <PyObject*>data
            self.deep = 0
            r = sproto_encode(st, buf, sz, _encode, &self)
            if r < 0:
                sz = sz*2
                buf = <char*>PyMem_Realloc(buf, sz)
            else:
                ret = buf[:r]
                return ret
    finally:
        PyMem_Free(buf)

cdef struct decode_ud:
    PyObject* data
    PyObject* key
    int deep
    int mainindex_tag

cdef int _decode(const sproto_arg *args) except SPROTO_CB_ERROR:
    cdef decode_ud *self = <decode_ud *>args.ud
    self_d = <dict>self.data
    # todo check deep
    if args.index != 0:
        if args.tagname not in self_d:
            l = []
            self_d[args.tagname] = l
        else:
            l = self_d[args.tagname]
        if args.index < 0:
            return 0

    ret = None 
    cdef decode_ud *sub
    if args.type == SPROTO_TINTEGER:
        ret = (<int64_t *>args.value)[0]
    elif args.type == SPROTO_TBOOLEAN:
        ret = True if (<int64_t *>args.value)[0] > 0 else False
    elif args.type == SPROTO_TSTRING:
        ret = (<char *>args.value)[:args.length]
    elif args.type == SPROTO_TSTRUCT:
        sub = <decode_ud *>PyMem_Malloc(sizeof(decode_ud))
        try:
            sub.deep = self.deep + 1
            sub_d = {}
            sub.data = <PyObject *>sub_d
            if args.mainindex >= 0:
                assert False, "todo"
            else:
                sub.mainindex_tag = -1
                r = sproto_decode(args.subtype, args.value, args.length, _decode, sub)
                if r < 0:
                    return SPROTO_CB_ERROR
                if r != args.length:
                    return r
                ret = sub_d
        finally:
            PyMem_Free(sub)
    else:
        raise Exception("Invalid type")

    if args.index > 0:
        l.append(ret)
    else:
        if self.mainindex_tag == args.tagid:
            assert False, "todo"
        self_d[args.tagname] = ret
    return 0

def decode(stobj, data):
    cdef sproto_type *st = <sproto_type*>PyCapsule_GetPointer(stobj, NULL)
    cdef char *buf = data
    cdef int size = len(data)
    cdef decode_ud self
    d = {}
    self.data = <PyObject *>d
    self.deep = 0
    self.mainindex_tag = -1
    r = sproto_decode(st, buf, size, _decode, &self)
    if r < 0:
        raise Exception("decode error")
    return d, r

cdef object __wrap_st(sproto_type *st):
    if st == NULL:
        return None
    return PyCapsule_New(st, NULL, NULL)

def newproto(pbin):
    cdef int size = len(pbin)
    cdef char* pb = pbin
    sp = sproto_create(pb, size)
    printf("sp: %p\n", sp)
    return PyCapsule_New(sp, NULL, <PyCapsule_Destructor>del_sproto)

def query_type(spobj, protoname):
    sp = <sproto*>PyCapsule_GetPointer(spobj, NULL)
    printf("sp: %p\n", <void*>sp)
    st = <sproto_type*>spt(sp, protoname)
    printf("st: %p\n", <void*>st)
    return PyCapsule_New(<void*>st, NULL, NULL)

def dump(spobj):
    sp = <sproto*>PyCapsule_GetPointer(spobj, NULL)
    sproto_dump(sp)

def protocol(spobj, name_or_tag):
    sp = <sproto*>PyCapsule_GetPointer(spobj, NULL)
    ret = None
    if isinstance(name_or_tag, int):
        tag = name_or_tag
        name = sproto_protoname(sp, name_or_tag)
        if not name:
            return None
        ret = name
    else:
        assert isinstance(name_or_tag, str)
        tag = sproto_prototag(sp, name_or_tag)
        if tag < 0:
            return None
        ret = tag
        
    req = sproto_protoquery(sp, tag, SPROTO_REQUEST)
    rsp = sproto_protoquery(sp, tag, SPROTO_RESPONSE)
    return ret, __wrap_st(req), __wrap_st(rsp)

def pack(data):
    cdef char* ptr = data
    cdef int size = len(data)
    cdef maxsz = (size + 2047) / 2048 * 2 + size + 2
    cdef char* buf = <char*>PyMem_Malloc(maxsz)
    try:
        out_sz = sproto_pack(ptr, size, buf, maxsz)
        if out_sz > maxsz:
            return None
        ret = buf[:out_sz]
        return ret
    finally:
        PyMem_Free(buf)

def unpack(data):
    cdef char* ptr = data
    cdef int size = len(data)
    cdef char* buf = <char*>PyMem_Malloc(prealloc)
    cdef r = 0
    try:
        r = sproto_unpack(ptr, size, buf, prealloc)
        if r > prealloc:
            buf = <char*>PyMem_Realloc(buf, r)
            r = sproto_unpack(ptr, size, buf, r)
        if r < 0:
            raise Exception("Invalid unpack stream")
        ret = buf[:r]
        return ret
    finally:
        PyMem_Free(buf)
    
