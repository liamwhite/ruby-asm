class FrameInfo
  attr_reader :first_index
  attr_reader :method_name
  attr_reader :scratch_registers

  PARAM_REGISTERS = [:rdi, :rsi, :rdx, :rcx, :r8, :r9, :r10, :rax]

  def initialize(method_name, param_count, first_index)
    @param_count = param_count
    @first_index = first_index
    @method_name = method_name
    @scratch_registers = []
    @range = (@first_index ... @first_index + @param_count)
  end

  def param?(var_num)
    @range.cover?(var_num)
  end

  def reg?(var_num)
    true # for now
  end

  def si(var_num)
    # XXX
  end

  def reg(var_num)
    PARAM_REGISTERS[@first_index - (@param_count + var_num)]
  end

  def local_reg(var_num)
    nil # XXX
  end

  def scratch
    scratched = PARAM_REGISTERS[(@param_count + @scratch_registers.size) .. -1][0]
    fail "Out of registers!" if scratched.nil?
    @scratch_registers.push(scratched)
    scratched
  end

  def unscratch(reg)
    @scratch_registers.delete(reg)
  end
end
