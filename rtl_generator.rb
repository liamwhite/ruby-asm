module RTLGenerator
  extend self

  def process(param_info, tree)
    tree = get_param_info_tree(param_info, tree)
    tree = insert_int_temps_tree(tree)
    tree = tail_call_tree(param_info, tree)
    tree = create_reg_info_tree(param_info, tree)
    tree = coalesce_branch_info_tree(tree)
    generate_asm_tree(param_info, tree)
  end

  def get_param_info_tree(param_info, tree)
    tree.map do |x|
      [x[0], x[1].map { |code| get_param_info(param_info, code) }]
    end
  end

  def get_param_info(param_info, code)
    insn, *args = code

    case insn
    when :branchif, :branchunless
      [insn, args[0], get_param_info(param_info, args[1])]
    when :leave
      [insn, get_param_info(param_info, args[0])]
    when :opt_le, :opt_minus, :opt_mult, :opt_eq
      [insn, get_param_info(param_info, args[0]), get_param_info(param_info, args[1])]
    when :opt_send_without_block
      [insn, args[0], *args[1..-1].map { |code| get_param_info(param_info, code) }]
    when :getlocal, :getlocal_OP__WC__0
      if param_info.param?(args[0])
        [:param, args[0] - param_info.first_index]
      else
        [insn, args[0]]
      end
    else
      code
    end
  end

  def insert_int_temps_tree(tree)
    tree.map do |x|
      [x[0], x[1].map { |code| insert_int_temps(code) }]
    end
  end

  def insert_int_temps(code)
    insn, *args = code

    case insn
    when :branchif, :branchunless
      [insn, args[0], insert_int_temps(args[1])]
    when :leave
      [insn, insert_int_temps(args[0])]
    when :opt_le, :opt_minus, :opt_mult, :opt_eq
      [insn, insert_int_temps(args[0]), insert_int_temps(args[1])]
    when :opt_send_without_block
      [insn, args[0], *args[1..-1].map { |code| insert_int_temps(code) }]
    when :putobject
      [:immediate, args[0]]
    when :putobject_OP_INT2FIX_O_0_C_
      [:immediate, 0]
    when :putobject_OP_INT2FIX_O_1_C_
      [:immediate, 1]
    else
      code
    end
  end

  def tail_call_tree(param_info, tree)
    tree.map do |x|
      [x[0], x[1].map { |code| tail_call(param_info, code) }]
    end
  end

  def tail_call(param_info, code)
    insn, *args = code

    case insn
    when :branchif, :branchunless
      [insn, args[0], tail_call(param_info, args[1])]
    when :opt_le, :opt_minus, :opt_mult, :opt_eq
      [insn, tail_call(param_info, args[0]), tail_call(param_info, args[1])]
    when :opt_send_without_block
      [insn, args[0], *args[1..-1].map { |code| tail_call(param_info, code) }]
    when :leave
      if args[0][0] == :opt_send_without_block && args[0][1] == param_info.method_name
        [:tail_call, args[0][2], *args[0][3..-1]]
      else
        code
      end
    else
      code
    end
  end

  def create_reg_info_tree(param_info, tree)
    tree.map do |x|
      [x[0], x[1].map { |code| create_reg_info(param_info, code) }]
    end
  end

  def create_reg_info(param_info, code)
    insn, *args = code

    case insn
    when :branchif, :branchunless
      [insn, args[0], create_reg_info(param_info, args[1])]
    when :opt_le, :opt_minus, :opt_mult, :opt_eq
      [insn, create_reg_info(param_info, args[0]), create_reg_info(param_info, args[1])]
    when :opt_send_without_block, :tail_call
      [insn, args[0], *args[1..-1].map { |code| create_reg_info(param_info, code) }]
    when :leave
      [insn, create_reg_info(param_info, args[0])]
    when :param
      if param_info.reg?(args[0])
        [:reg, param_info.reg(args[0])]
      else
        [:stack, param_info.si(args[0])]
      end
    else
      code
    end
  end

  BRANCHIF_TARGETS = {
    opt_lt:  :jl,
    opt_le:  :jle,
    opt_gt:  :jg,
    opt_ge:  :jge,
    opt_eq:  :je,
    opt_neq: :jne,
  }

  BRANCHUNLESS_TARGETS = {
    opt_lt:  :jge,
    opt_le:  :jg,
    opt_gt:  :jle,
    opt_ge:  :jl,
    opt_eq:  :jne,
    opt_neq: :je,
  }

  # coalesce branchif/branchunless with comparison targets
  # so that flags can be used correctly in the output
  def coalesce_branch_info_tree(tree)
    tree.map do |x|
      [x[0], x[1].map { |code| coalesce_branch_info(code) }]
    end
  end

  def coalesce_branch_info(code)
    insn, *args = code

    case insn
    when :branchif
      if args.size == 2 && BRANCHIF_TARGETS.key?(args[1][0])
        [BRANCHIF_TARGETS[args[1][0]], args[0], *args[1][1..-1]]
      else
        code
      end
    when :branchunless
      if args.size == 2 && BRANCHUNLESS_TARGETS.key?(args[1][0])
        [BRANCHUNLESS_TARGETS[args[1][0]], args[0], *args[1][1..-1]]
      else
        code
      end
    else
      code
    end
  end

  def generate_asm_tree(param_info, tree)
    output = "#{param_info.method_name}:\n"
    output << tree.map { |x| "#{x[0]}:\n#{x[1].map { |code| generate_asm(param_info, code) }.join("")}" }.join("\n")
    output
  end

  def generate_asm(param_info, code)
    insn, *args = code

    case insn
    when :jl, :jle, :jg, :jge, :je, :jne
      arg1 = args[1][1]
      arg2 = args[2][1]
      "  cmp #{arg1}, #{arg2}\n" \
      "  #{insn} #{args[0]}\n"
    when :leave
      "  mov rax, #{args[0][1]}\n" \
      "  ret\n"
    when :tail_call
      old_scratches = param_info.scratch_registers.dup
      asm = args[1..-1].map { |arg| generate_asm(param_info, arg) }.join("")
      new_scratches = param_info.scratch_registers - old_scratches

      ParamInfo::PARAM_REGISTERS[0 ... new_scratches.size].zip(new_scratches).each do |dest, src|
        asm << "  mov #{dest}, #{src}\n"
      end

      asm << "  jmp #{param_info.method_name}\n"
      asm
    when :opt_minus
      reg = param_info.scratch
      "  mov #{reg}, #{args[0][1]}\n" \
      "  sub #{reg}, #{args[1][1]}\n"
    when :opt_mult
      # necessary to spill rax to access mul instruction
      reg = param_info.scratch
      "  push rax\n" \
      "  mov rax, #{args[0][1]}\n" \
      "  mul #{args[1][1]}\n" \
      "  mov #{reg}, rax\n" \
      "  pop rax\n"
    end
  end

  class ParamInfo
    attr_reader :first_index
    attr_reader :method_name
    attr_reader :scratch_registers

    PARAM_REGISTERS = [:rdi, :rsi, :rcx, :r8, :r9]

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

    def scratch
      scratched = PARAM_REGISTERS[(@param_count + @scratch_registers.size) .. -1][0]
      @scratch_registers.push(scratched)
      scratched
    end

    def unscratch(reg)
      @scratch_registers.delete(reg)
    end
  end
end
