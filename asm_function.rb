require 'ffi'

module ASMFunction
  extend FFI::Library
  ffi_lib FFI::Library::LIBC

  PROT_NONE  = 0x0
  PROT_READ  = 0x1
  PROT_WRITE = 0x2
  PROT_EXEC  = 0x4

  MAP_PRIVATE   = 0x02
  MAP_ANONYMOUS = 0x20

  NULL = FFI::Pointer.new(0x0)

  attach_function :mmap, [:pointer, :size_t, :int, :int, :int, :int], :pointer
  attach_function :munmap, [:pointer, :size_t], :int
  attach_function :mprotect, [:pointer, :size_t, :int], :int

  def self.mapping_sizes
    $mapping_sizes ||= {}
  end

  def self.map_function(code, ret, args)
    size = code.bytesize
    mem = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, 0, 0)
    mem.put_bytes(0, code)
    mprotect(mem, size, PROT_READ | PROT_EXEC)
    mapping_sizes[mem.address] = size
    FFI::Function.new(ret, args, mem)
  end

  def self.unmap_function(func)
    munmap(FFI::Pointer.new(func.address), mapping_sizes[mem.address])
    mapping_sizes.delete(mem.address)
  end
end
