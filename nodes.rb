class RunInfo
  attr_reader :dest_reg, :children

  def initialize(dest_reg, children)
    @dest_reg = dest_reg
    @children = children
  end
end

class InstructionListNode
  def initialize(label, children)
    @label = label
    @children = children
  end

  def run(frame_info)
    @children.map{|c| c.run(frame_info).children }.flatten(1)
  end
end

class BranchIfNode
  BRANCHIF_TARGETS = {
    opt_lt:  :jl,
    opt_le:  :jle,
    opt_gt:  :jg,
    opt_ge:  :jge,
    opt_eq:  :je,
    opt_neq: :jne,
  }

  def initialize(target, condition)
    @target = target
    @condition = condition
  end

  def run(frame_info)
    if @condition.is_a?(ComparisonNode)
      left_cond = @condition.left.run(frame_info)
      right_cond = @condition.right.run(frame_info)
      ri = RunInfo.new(nil, [*left_cond.children, *right_cond.children, [:cmp, left_cond.dest_reg, right_cond.dest_reg], [BRANCHIF_TARGETS[@condition.type], @target]])
      frame_info.unscratch(left_cond.dest_reg)
      frame_info.unscratch(right_cond.dest_reg)
      ri
    else
      cond = @condition.run(frame_info)
      ri = RunInfo.new(nil, [*cond.children, [:cmp, cond.dest_reg, 0], [:jnz, @target]])
      frame_info.unscratch(cond.dest_reg)
      ri
    end
  end
end

class BranchUnlessNode
  BRANCHUNLESS_TARGETS = {
    opt_lt:  :jge,
    opt_le:  :jg,
    opt_gt:  :jle,
    opt_ge:  :jl,
    opt_eq:  :jne,
    opt_neq: :je,
  }

  def initialize(target, condition)
    @target = target
    @condition = condition
  end

  def run(frame_info)
    if @condition.is_a?(ComparisonNode)
      left_cond = @condition.left.run(frame_info)
      right_cond = @condition.right.run(frame_info)
      ri = RunInfo.new(nil, [*left_cond.children, *right_cond.children, [:cmp, left_cond.dest_reg, right_cond.dest_reg], [BRANCHUNLESS_TARGETS[@condition.type], @target]])
      frame_info.unscratch(left_cond.dest_reg)
      frame_info.unscratch(right_cond.dest_reg)
      ri
    else
      cond = @condition.run(frame_info)
      ri = RunInfo.new(nil, [*cond.children, [:cmp, cond.dest_reg, 0], [:jz, @target]])
      frame_info.unscratch(cond.dest_reg)
      ri
    end
  end
end

class JumpNode
  def initialize(target, children)
    @target = target
    @children = children
  end

  def run(frame_info)
    runinfos = @children.map{|c| c.run(frame_info) }
    runinfos.each {|r| frame_info.unscratch(r.dest_reg) }
    insns = runinfos.map{|r| r.children }.flatten(1)
    RunInfo.new(nil, [*insns, [:jmp, @target]])
  end
end

class ComparisonNode
  attr_reader :type, :left, :right

  def initialize(type, left, right)
    @type = type
    @left = left
    @right = right
  end

  def run(frame_info)
    fail "Comparison not implemented"
  end
end

class RegisterParameterNode
  def initialize(num)
    @num = num
  end

  def run(frame_info)
    RunInfo.new(frame_info.reg(@num), [])
  end
end

class ImmediateNode
  attr_reader :value

  def initialize(value)
    @value = value
  end

  def run(frame_info)
    # XXX
    reg = frame_info.scratch
    RunInfo.new(reg, [[:mov, reg, @value]])
  end
end

class AdditionNode
  def initialize(left, right)
    @left = left
    @right = right
  end

  def run(frame_info)
    left_cond = @left.run(frame_info)
    right_cond = @right.run(frame_info)
    reg = frame_info.scratch
    ri = RunInfo.new(reg, [*left_cond.children, *right_cond.children, [:mov, reg, left_cond.dest_reg], [:add, reg, right_cond.dest_reg]])
    frame_info.unscratch(left_cond.dest_reg)
    frame_info.unscratch(right_cond.dest_reg)
    p ri.children
    ri
  end
end

class SubtractionNode
  def initialize(left, right)
    @left = left
    @right = right
  end

  def run(frame_info)
    left_cond = @left.run(frame_info)
    right_cond = @right.run(frame_info)
    reg = frame_info.scratch
    ri = RunInfo.new(reg, [*left_cond.children, *right_cond.children, [:mov, reg, left_cond.dest_reg], [:sub, reg, right_cond.dest_reg]])
    left_cond.unscratch(left_cond.dest_reg)
    right_cond.unscratch(right_cond.dest_reg)
    ri
  end
end

class MultiplicationNode
  def initialize(left, right)
    @left = left
    @right = right
  end

  def run(frame_info)
    left_cond = @left.run(frame_info)
    right_cond = @right.run(frame_info)
    reg = frame_info.scratch
    ri = RunInfo.new(reg, [*left_cond.children, *right_cond.children, [:push, :rax], [:mov, :rax, left_cond.dest_reg], [:mul, right_cond.dest_reg], [:mov, reg, :rax], [:pop, :rax]])
    frame_info.unscratch(left_cond.dest_reg)
    frame_info.unscratch(right_cond.dest_reg)
    ri
  end
end

class DivisionNode
  def initialize(left, right)
    @left = left
    @right = right
  end

  def run(frame_info)
    left_cond = @left.run(frame_info)
    right_cond = @right.run(frame_info)
    reg = frame_info.scratch
    ri = RunInfo.new(reg, [*left_cond.children, *right_cond.children, [:push, :rax], [:push, :rdx], [:mov, :rdx, 0], [:mov, :rax, left_cond.dest_reg], [:div, right_cond.dest_reg], [:mov, reg, :rax], [:pop, :rdx], [:pop, :rax]])
    frame_info.unscratch(left_cond.dest_reg)
    frame_info.unscratch(right_cond.dest_reg)
    ri
  end
end

class ModuloNode
  def initialize(left, right)
    @left = left
    @right = right
  end

  def run(frame_info)
    left_cond = @left.run(frame_info)
    right_cond = @right.run(frame_info)
    reg = frame_info.scratch
    ri = RunInfo.new(reg, [*left_cond.children, *right_cond.children, [:push, :rax], [:push, :rdx], [:mov, :rdx, 0], [:mov, :rax, left_cond.dest_reg], [:div, right_cond.dest_reg], [:mov, reg, :rdx], [:pop, :rdx], [:pop, :rax]])
    frame_info.unscratch(left_cond.dest_reg)
    frame_info.unscratch(right_cond.dest_reg)
    ri
  end
end

class ReturnNode
  def initialize(target)
    @target = target
  end

  def run(frame_info)
    # unconditionally overwrite rax
    target_cond = @target.run(frame_info)
    ri = RunInfo.new(:rax, [*target_cond.children, [:mov, :rax, target_cond.dest_reg]])
    frame_info.unscratch(target_cond.dest_reg)
    ri
  end
end

class SendWithoutBlockNode
  ARGUMENTS_ORDER = [:rdi, :rsi, :rdx, :rcx, :r8, :r9]

  def initialize(method_name, receiver, arguments)
    @method_name = method_name
    @receiver = receiver
    @arguments = arguments
  end

  def run(frame_info)
    runinfos = @arguments.map{|a| a.run(frame_info) }
    runinfos.each {|ri| frame_info.unscratch(ri.dest_reg) }
    insns = runinfos.map{|i| i.children }.flatten(1)

    if @method_name == frame_info.method_name
      # this is a tail call
      ARGUMENTS_ORDER[0 ... runinfos.size].zip(runinfos.map(&:dest_reg)).each do |dest, src|
        next if dest == src
        insns << [:mov, dest, src]
      end
      RunInfo.new(nil, [*insns, [:jmp, frame_info.method_name]])
    else
      RunInfo.new(nil, [*insns, [:uic, @method_name]])
      #fail "Non-tail calls not implemented"
    end
  end
end

class SetLocalNode
  def initialize(local_num, child)
    @local_num = local_num
    @child = child
  end

  def run(frame_info)
    child_cond = @child.run(frame_info)
    reg = frame_info.local_reg(@local_num)
    frame_info.unscratch(child_cond.dest_reg)
    RunInfo.new(nil, [*child_cond.children, [:mov, reg, child_cond.dest_reg]])
  end
end

class GetLocalNode
  def initialize(local_num)
    @local_num = local_num
  end

  def run(frame_info)
    reg = frame_info.local_reg(@local_num)
    RunInfo.new(reg, [])
  end
end
