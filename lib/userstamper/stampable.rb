# Extends the stamping functionality of ActiveRecord by automatically recording the model
# responsible for creating, updating the current object. See the +Stamper+ and
# +ControllerAdditions+ modules for further documentation on how the entire process works.
module Userstamper::Stampable
  extend ActiveSupport::Concern

  included do
    # Should ActiveRecord record userstamps? Defaults to true.
    class_attribute  :record_userstamp
    self.record_userstamp = true

    class_attribute  :stamper_class_name

    before_validation :set_updater_attribute, if: :record_userstamp
    before_validation :set_creator_attribute, on: :create, if: :record_userstamp
    before_save :set_updater_attribute, if: :record_userstamp
    before_create :set_creator_attribute, if: :record_userstamp
  end

  module ClassMethods
    def columns(*)
      columns = super
      return columns if defined?(@stamper_initialized) && @stamper_initialized

      add_userstamp_associations({})
      columns
    end

    # This method customizes how the gem functions. For example:
    #
    #   class Post < ActiveRecord::Base
    #     stampable stamper_class_name: Person.name
    #   end
    #
    # the gem configuration.
    def stampable(options = {})
      self.stamper_class_name = options.delete(:stamper_class_name) if options.key?(:stamper_class_name)

      add_userstamp_associations(options)
    end

    # Temporarily allows you to turn stamping off. For example:
    #
    #   Post.without_stamps do
    #     post = Post.find(params[:id])
    #     post.update_attributes(params[:post])
    #     post.save
    #   end
    def without_stamps
      original_value = self.record_userstamp
      self.record_userstamp = false
      yield
    ensure
      self.record_userstamp = original_value
    end

    def stamper_class #:nodoc:
      stamper_class_name.to_s.camelize.constantize rescue nil
    end

    private

    # Defines the associations for Userstamper.
    def add_userstamp_associations(options)
      @stamper_initialized = true
      Userstamper::Utilities.remove_association(self, :creator)
      Userstamper::Utilities.remove_association(self, :updater)

      associations = Userstamper::Utilities.available_association_columns(self)
      return if associations.nil?

      config = Userstamper.config
      klass = stamper_class.try(:name)
      relation_options = options.reverse_merge(class_name: klass)

      belongs_to :creator, **relation_options.reverse_merge(foreign_key: config.creator_attribute, required: false) if associations.first
      belongs_to :updater, **relation_options.reverse_merge(foreign_key: config.updater_attribute, required: false) if associations.second
    end
  end

  private

  def has_stamper?
    !self.class.stamper_class.nil? && !self.class.stamper_class.stamper.nil?
  end

  def set_creator_attribute
    return unless has_stamper?

    creator_association = self.class.reflect_on_association(:creator)
    return unless creator_association
    return if creator.present?

    Userstamper::Utilities.assign_stamper(self, creator_association)
  end

  def set_updater_attribute
    return unless has_stamper?

    updater_association = self.class.reflect_on_association(:updater)
    return unless updater_association
    return if !new_record? && !changed?

    Userstamper::Utilities.assign_stamper(self, updater_association)
  end
end
