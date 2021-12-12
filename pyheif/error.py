import _libheif_cffi


class HeifError(Exception):
    def __init__(self, *, code, subcode, message):
        self.code = code
        self.subcode = subcode
        self.message = message

    def __str__(self):
        return f'Code: {self.code}, Subcode: {self.subcode}, Message: "{self.message}"'

    def __repr__(self):
        return f'HeifError({self.code}, {self.subcode}, "{self.message}"'


def _assert_success(error):
    if error.code != 0:
        raise HeifError(
            code=error.code,
            subcode=error.subcode,
            message=_libheif_cffi.ffi.string(error.message).decode(),
        )
