module RubyCompiler
  extend self

  def process(method)
    disasm = RubyVM::InstructionSequence.of(method)
      .to_a[-1]
      .reject!{|x| [:RUBY_EVENT_LINE, :RUBY_EVENT_RETURN, :RUBY_EVENT_CALL].include?(x) || x.is_a?(Integer) }

    label_stack = labelify(disasm)
    infix_tree = infixify(label_stack)
  end

  def labelify(disasm)
    label_stack = []
    disasm.unshift(:label_0) unless disasm[0].is_a?(Symbol)
    current_stack = []
    disasm.each do |x|
      if x.is_a?(Symbol)
        label_stack.push(current_stack)
        current_stack = []
      end  
      current_stack.push(x)
    end
    label_stack.push(current_stack)
    label_stack.shift # delete extra [] at start
    label_stack
  end

  def infixify(label_stack)
    label_stack.map! do |label, *operands|
      operator_stack = []
      operands.each do |x, *args|
        case x
        when :opt_le
          argument = operator_stack.pop
          receiver = operator_stack.pop
          operator_stack.push [:opt_le, receiver, argument]
        when :branchunless
          receiver = operator_stack.pop
          operator_stack.push [:branchunless, *args, receiver]
        when :branchif
          receiver = operator_stack.pop
          operator_stack.push [:branchif, *args, receiver]
        when :opt_eq
          argument = operator_stack.pop
          receiver = operator_stack.pop
          operator_stack.push [:opt_eq, receiver, argument]
        when :opt_minus
          argument = operator_stack.pop
          receiver = operator_stack.pop
          operator_stack.push [:opt_minus, receiver, argument]
        when :opt_mult
          argument = operator_stack.pop
          receiver = operator_stack.pop
          operator_stack.push [:opt_mult, receiver, argument]
        when :opt_send_without_block
          arguments = operator_stack.pop(args[0][:orig_argc])
          receiver = operator_stack.pop
          operator_stack.push [:opt_send_without_block, args[0][:mid], receiver, *arguments]
        when :leave
          return_val = operator_stack.pop
          operator_stack.push [:leave, return_val]
        when :trace
          # nop
        else
          operator_stack.push [x, *args]
        end
      end

      [label, operator_stack]
    end
  end
end
