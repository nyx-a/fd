
module B
  # namespace
end

class B::Structure
  def initialize **hash
    for k,v in hash
      setter = "#{k}=".to_sym
      if respond_to? setter
        self.send setter, v
      else
        raise KeyError, "No such element `#{k}`"
      end
    end
  end

  def to_hash
    self.instance_variables.to_h do
      [
        _1[1..].to_sym,
        instance_variable_get(_1),
      ]
    end
  end
end

