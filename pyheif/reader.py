import builtins
import functools
import pathlib
import warnings

import _libheif_cffi
from . import constants as _constants
from . import error as _error


class HeifFile:
    def __init__(
        self,
        *,
        size,
        has_alpha,
        bit_depth,
        transformations,
        metadata,
        color_profile,
        data,
        stride,
    ):
        self.size = size
        self.has_alpha = has_alpha
        self.mode = "RGBA" if has_alpha else "RGB"
        self.bit_depth = bit_depth
        self.transformations = transformations
        self.metadata = metadata
        self.color_profile = color_profile
        self.data = data
        self.stride = stride

    def __repr__(self):
        return (
            f"<{self.__class__.__name__} {self.size[0]}x{self.size[1]} {self.mode} "
            f"with {str(len(self.data)) + ' bytes' if self.data else 'no'} data>"
        )

    def load(self):
        return self  # already loaded

    def close(self):
        pass  # TODO: release self.data here?


class UndecodedHeifFile(HeifFile):
    def __init__(
        self, heif_handle, *, apply_transformations, convert_hdr_to_8bit, **kwargs
    ):
        self._heif_handle = heif_handle
        self.apply_transformations = apply_transformations
        self.convert_hdr_to_8bit = convert_hdr_to_8bit
        super().__init__(data=None, stride=None, **kwargs)

    def load(self):
        self.data, self.stride = _read_heif_image(self._heif_handle, self)
        self.close()
        self.__class__ = HeifFile
        return self

    def close(self):
        # Don't call super().close() here, we don't need to free bytes.
        if hasattr(self, "_heif_handle"):
            del self._heif_handle


def check(fp):
    magic = _get_bytes(fp, 12)
    filetype_check = _libheif_cffi.lib.heif_check_filetype(magic, len(magic))
    return filetype_check


def read_heif(fp, apply_transformations=True):
    warnings.warn("read_heif is deprecated, use read instead", DeprecationWarning)
    return read(fp, apply_transformations=apply_transformations)


def read(fp, *, apply_transformations=True, convert_hdr_to_8bit=True):
    heif_file = open(
        fp,
        apply_transformations=apply_transformations,
        convert_hdr_to_8bit=convert_hdr_to_8bit,
    )
    return heif_file.load()


def open(fp, *, apply_transformations=True, convert_hdr_to_8bit=True):
    d = _get_bytes(fp)
    return _read_heif_bytes(d, apply_transformations, convert_hdr_to_8bit)


def _get_bytes(fp, length=None):
    if isinstance(fp, (str, pathlib.Path)):
        with builtins.open(fp, "rb") as f:
            d = f.read(length or -1)
    elif hasattr(fp, "read"):
        d = fp.read(length or -1)
    else:
        d = bytes(fp)[:length]

    return d


def _keep_refs(destructor, **refs):
    """
    Keep refs to passed arguments until `inner` callback exist.
    This prevents collecting parent objects until all children collcted.
    """

    def inner(cdata):
        return destructor(cdata)

    inner._refs = refs
    return inner


def _read_heif_bytes(d, apply_transformations, convert_hdr_to_8bit):
    magic = d[:12]
    filetype_check = _libheif_cffi.lib.heif_check_filetype(magic, len(magic))
    if filetype_check == _constants.heif_filetype_no:
        raise ValueError("Input is not a HEIF/AVIF file")
    elif filetype_check == _constants.heif_filetype_yes_unsupported:
        warnings.warn("Input is an unsupported HEIF/AVIF file type - trying anyway!")

    ctx = _libheif_cffi.lib.heif_context_alloc()
    collect = _keep_refs(_libheif_cffi.lib.heif_context_free, data=d)
    ctx = _libheif_cffi.ffi.gc(ctx, collect, size=len(d))
    return _read_heif_context(ctx, d, apply_transformations, convert_hdr_to_8bit)


def _read_heif_context(ctx, d, apply_transformations, convert_hdr_to_8bit):
    error = _libheif_cffi.lib.heif_context_read_from_memory_without_copy(
        ctx, d, len(d), _libheif_cffi.ffi.NULL
    )
    if error.code != 0:
        raise _error.HeifError(
            code=error.code,
            subcode=error.subcode,
            message=_libheif_cffi.ffi.string(error.message).decode(),
        )

    p_handle = _libheif_cffi.ffi.new("struct heif_image_handle **")
    error = _libheif_cffi.lib.heif_context_get_primary_image_handle(ctx, p_handle)
    if error.code != 0:
        raise _error.HeifError(
            code=error.code,
            subcode=error.subcode,
            message=_libheif_cffi.ffi.string(error.message).decode(),
        )
    collect = _keep_refs(_libheif_cffi.lib.heif_image_handle_release, ctx=ctx)
    handle = _libheif_cffi.ffi.gc(p_handle[0], collect)
    return _read_heif_handle(handle, apply_transformations, convert_hdr_to_8bit)


def _read_heif_handle(handle, apply_transformations, convert_hdr_to_8bit):
    if apply_transformations:
        width = _libheif_cffi.lib.heif_image_handle_get_width(handle)
        height = _libheif_cffi.lib.heif_image_handle_get_height(handle)
    else:
        width = _libheif_cffi.lib.heif_image_handle_get_ispe_width(handle)
        height = _libheif_cffi.lib.heif_image_handle_get_ispe_height(handle)
    has_alpha = bool(_libheif_cffi.lib.heif_image_handle_has_alpha_channel(handle))
    bit_depth = _libheif_cffi.lib.heif_image_handle_get_luma_bits_per_pixel(handle)

    transformations = _read_transformations(handle)
    metadata = _read_metadata(handle)
    color_profile = _read_color_profile(handle)

    heif_file = UndecodedHeifFile(
        handle,
        size=(width, height),
        has_alpha=has_alpha,
        bit_depth=bit_depth,
        transformations=transformations,
        metadata=metadata,
        color_profile=color_profile,
        apply_transformations=apply_transformations,
        convert_hdr_to_8bit=convert_hdr_to_8bit,
    )
    return heif_file


def _read_transformations(handle):
    transformations = _libheif_cffi.lib.heif_transformations_alloc()
    transformations = _libheif_cffi.ffi.gc(
        transformations, _libheif_cffi.lib.heif_transformations_free
    )
    _libheif_cffi.lib.heif_image_handle_get_transformations(handle, transformations)
    return {
        "crop": (
            transformations.crop_left,
            transformations.crop_top,
            transformations.crop_width,
            transformations.crop_height,
        ),
        "orientation_tag": transformations.orientation_tag,
    }


def _read_metadata(handle):
    block_count = _libheif_cffi.lib.heif_image_handle_get_number_of_metadata_blocks(
        handle, _libheif_cffi.ffi.NULL
    )
    if block_count == 0:
        return

    metadata = []
    ids = _libheif_cffi.ffi.new("heif_item_id[]", block_count)
    _libheif_cffi.lib.heif_image_handle_get_list_of_metadata_block_IDs(
        handle, _libheif_cffi.ffi.NULL, ids, block_count
    )
    for i in range(len(ids)):
        metadata_type = _libheif_cffi.lib.heif_image_handle_get_metadata_type(
            handle, ids[i]
        )
        metadata_type = _libheif_cffi.ffi.string(metadata_type).decode()
        data_length = _libheif_cffi.lib.heif_image_handle_get_metadata_size(
            handle, ids[i]
        )
        p_data = _libheif_cffi.ffi.new("char[]", data_length)
        error = _libheif_cffi.lib.heif_image_handle_get_metadata(handle, ids[i], p_data)
        if error.code != 0:
            raise _error.HeifError(
                code=error.code,
                subcode=error.subcode,
                message=_libheif_cffi.ffi.string(error.message).decode(),
            )
        data_buffer = _libheif_cffi.ffi.buffer(p_data, data_length)
        data = bytes(data_buffer)
        if metadata_type == "Exif":
            # skip TIFF header, first 4 bytes
            data = data[4:]
        metadata.append({"type": metadata_type, "data": data})

    return metadata


def _read_color_profile(handle):
    profile_type = _libheif_cffi.lib.heif_image_handle_get_color_profile_type(handle)
    if profile_type == _constants.heif_color_profile_type_not_present:
        return

    color_profile = {"type": "unknown", "data": None}
    if profile_type == _constants.heif_color_profile_type_nclx:
        color_profile["type"] = "nclx"
        data_length = _libheif_cffi.ffi.sizeof("struct heif_color_profile_nclx")
        pp_data = _libheif_cffi.ffi.new("struct heif_color_profile_nclx * *")
        error = _libheif_cffi.lib.heif_image_handle_get_nclx_color_profile(
            handle, pp_data
        )
        p_data = _libheif_cffi.ffi.gc(
            pp_data[0], _libheif_cffi.lib.heif_nclx_color_profile_free
        )

    else:
        if profile_type == _constants.heif_color_profile_type_rICC:
            color_profile["type"] = "rICC"
        elif profile_type == _constants.heif_color_profile_type_prof:
            color_profile["type"] = "prof"
        data_length = _libheif_cffi.lib.heif_image_handle_get_raw_color_profile_size(
            handle
        )
        p_data = _libheif_cffi.ffi.new("char[]", data_length)
        error = _libheif_cffi.lib.heif_image_handle_get_raw_color_profile(
            handle, p_data
        )

    if error.code != 0:
        raise _error.HeifError(
            code=error.code,
            subcode=error.subcode,
            message=_libheif_cffi.ffi.string(error.message).decode(),
        )
    data_buffer = _libheif_cffi.ffi.buffer(p_data, data_length)
    data = bytes(data_buffer)
    color_profile["data"] = data

    return color_profile


def _read_heif_image(handle, heif_file):
    colorspace = _constants.heif_colorspace_RGB
    if heif_file.convert_hdr_to_8bit or heif_file.bit_depth <= 8:
        if heif_file.has_alpha:
            chroma = _constants.heif_chroma_interleaved_RGBA
        else:
            chroma = _constants.heif_chroma_interleaved_RGB
    else:
        if heif_file.has_alpha:
            chroma = _constants.heif_chroma_interleaved_RRGGBBAA_BE
        else:
            chroma = _constants.heif_chroma_interleaved_RRGGBB_BE

    p_options = _libheif_cffi.lib.heif_decoding_options_alloc()
    p_options = _libheif_cffi.ffi.gc(
        p_options, _libheif_cffi.lib.heif_decoding_options_free
    )
    p_options.ignore_transformations = int(not heif_file.apply_transformations)
    p_options.convert_hdr_to_8bit = int(heif_file.convert_hdr_to_8bit)

    p_img = _libheif_cffi.ffi.new("struct heif_image **")
    error = _libheif_cffi.lib.heif_decode_image(
        handle, p_img, colorspace, chroma, p_options,
    )
    if error.code != 0:
        raise _error.HeifError(
            code=error.code,
            subcode=error.subcode,
            message=_libheif_cffi.ffi.string(error.message).decode(),
        )
    img = p_img[0]

    p_stride = _libheif_cffi.ffi.new("int *")
    p_data = _libheif_cffi.lib.heif_image_get_plane_readonly(
        img, _constants.heif_channel_interleaved, p_stride
    )
    stride = p_stride[0]

    data_length = heif_file.size[1] * stride

    # Release image as soon as no references to p_data left
    collect = functools.partial(_release_heif_image, img)
    p_data = _libheif_cffi.ffi.gc(p_data, collect, size=data_length)

    # ffi.buffer obligatory keeps a reference to p_data
    data_buffer = _libheif_cffi.ffi.buffer(p_data, data_length)

    return data_buffer, stride


def _release_heif_image(img, p_data=None):
    _libheif_cffi.lib.heif_image_release(img)
