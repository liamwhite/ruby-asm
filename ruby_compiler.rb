require 'nodes'

module RubyCompiler
  extend self

  def process(frame_info, method)
    disasm = RubyVM::InstructionSequence.of(method)
      .to_a[-1]
      .reject!{|x| [:RUBY_EVENT_LINE, :RUBY_EVENT_RETURN, :RUBY_EVENT_CALL].include?(x) || x.is_a?(Integer) }

    label_stack = labelify(disasm)
    infix_tree = treeify(frame_info, label_stack)
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

  OP_TO_NODE = {
    opt_plus: AdditionNode,
    opt_minus: SubtractionNode,
    opt_mult: MultiplicationNode,
    opt_div: DivisionNode,
    opt_mod: ModuloNode
  }

  def treeify(frame_info, label_stack)
    label_stack.map! do |label, *operands|
      operator_stack = []
      operands.each do |x, *args|
        case x
        when :opt_le, :opt_lt, :opt_ge, :opt_gt, :opt_eq, :opt_neq
          argument = operator_stack.pop
          receiver = operator_stack.pop
          operator_stack.push ComparisonNode.new(x, argument, receiver)
        when :opt_plus, :opt_minus, :opt_mult, :opt_div, :opt_mod
          argument = operator_stack.pop
          receiver = operator_stack.pop
          operator_stack.push OP_TO_NODE[x].new(receiver, argument)
        when :setlocal_OP__WC__0
          assignment_val = operator_stack.pop
          operator_stack.push SetLocalNode.new(args[0], assignment_val)
        when :branchif
          receiver = operator_stack.pop
          operator_stack.push BranchIfNode.new(args[0], receiver)
        when :branchunless
          receiver = operator_stack.pop
          operator_stack.push BranchUnlessNode.new(args[0], receiver)
        when :opt_send_without_block
          arguments = operator_stack.pop(args[0][:orig_argc])
          receiver = operator_stack.pop
          operator_stack.push SendWithoutBlockNode.new(args[0][:mid], receiver, arguments)
        when :leave
          return_val = operator_stack.pop
          operator_stack.push ReturnNode.new(return_val)
        when :trace
          # nop
        when :putobject
          fail "Unhandled immediate" if !args[0].is_a?(Integer)
          operator_stack.push ImmediateNode.new(args[0])
        when :putobject_OP_INT2FIX_O_0_C_
          operator_stack.push ImmediateNode.new(0)
        when :putobject_OP_INT2FIX_O_1_C_
          operator_stack.push ImmediateNode.new(1)
        when :jump
          operator_stack = [JumpNode.new(args[0], operator_stack)]
        when :getlocal_OP__WC__0
          operator_stack.push GetLocalNode.new(args[0])
        else
          puts "Discarding lonely instruction #{x}"
          #operator_stack.push [x, *args]
        end
      end

      InstructionListNode.new(label, operator_stack)
    end
  end
end
