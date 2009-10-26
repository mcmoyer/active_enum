module ActiveEnum
  class EnumNotFound < StandardError; end

  module Extensions

    def self.included(base)
      base.extend ClassMethods
      base.class_inheritable_accessor :enumerated_attributes
      base.enumerated_attributes = {}
    end

    module ClassMethods

      # Declare an attribute to be enumerated by an enum class
      #
      #   enumerate :sex, :with => Sex
      #   enumerate :sex # implies a Sex enum class exists
      #
      def enumerate(attribute, options={})
        enum = options[:with]
        unless enum
          enum = attribute.to_s.classify.constantize
        end

        self.enumerated_attributes[attribute.to_sym] = enum

        define_active_enum_read_method(attribute)
        define_active_enum_write_method(attribute)
        define_active_enum_question_method(attribute)
      rescue NameError => e
        raise e unless e.message =~ /uninitialized constant/
        raise ActiveEnum::EnumNotFound, "Enum class could not be found for attribute '#{attribute}' in class #{self}. Specify the enum class using the :with option."
      end

      def enum_for(attribute)
        self.enumerated_attributes[attribute.to_sym]
      end

      # Define read method to allow an argument for the enum component
      #
      #   user.sex
      #   user.sex(:id)
      #   user.sex(:name)
      #   user.sex(:enum)
      #
      def define_active_enum_read_method(attribute)
        unless instance_method_already_implemented?(attribute)
          define_read_method(attribute.to_sym, attribute.to_s, columns_hash[attribute])
        end

        old_method = "#{attribute}_without_enum"
        define_method("#{attribute}_with_enum") do |*arg|
          arg = arg.first
          value = send(old_method)

          enum = self.class.enum_for(attribute)
          case arg
          when :id
            value if enum.find_by_id(value)
          when :name
            enum[value]
          when :enum
            enum
          else
            ActiveEnum.use_name_as_value ? enum[value] : value
          end
        end

        alias_method_chain attribute, :enum
      end

      # Define write method to also handle enum value
      #
      #   user.sex = 1
      #   user.sex = :male
      #
      def define_active_enum_write_method(attribute)
        unless instance_method_already_implemented?("#{attribute}=")
          define_write_method(attribute.to_sym)
        end

        old_method = "#{attribute}_without_enum="
        define_method("#{attribute}_with_enum=") do |arg|
          enum = self.class.enum_for(attribute)
          if arg.is_a?(Symbol)
            value = enum[arg]
            send(old_method, value)
          else
            send(old_method, arg)
          end
        end

        alias_method_chain "#{attribute}=".to_sym, :enum
      end

      # Define question method to check enum value against attribute value
      #
      #   user.sex?(:male)
      #
      def define_active_enum_question_method(attribute)
        define_question_method(attribute) unless instance_method_already_implemented?("#{attribute}?")

        old_method = "#{attribute}_without_enum?"
        define_method("#{attribute}_with_enum?") do |*arg|
          arg = arg.first
          if arg
            send(attribute) == self.class.enum_for(attribute)[arg]
          else
            send(old_method)
          end
        end
        alias_method_chain "#{attribute}?".to_sym, :enum
      end

    end

  end
end

ActiveRecord::Base.send :include, ActiveEnum::Extensions
