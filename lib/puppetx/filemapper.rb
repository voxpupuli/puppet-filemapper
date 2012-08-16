require 'puppet/util/filetype'

# Forward declaration
module PuppetX; end

module PuppetX::FileMapper

  # Copy all desired resource properties into this resource for generation upon flush
  #
  # This method is necessary for the provider to be ensurable
  def create
    @resource.class.validproperties.each do |property|
      if value = @resource.should(property)
        @property_hash[property] = value
      end
    end

    # FIXME This is a hack. The common convention is to use :name as the
    # namevar and use it as a property, but treat it as a param. If this is
    # treated as a property then it needs to be copied in.
    @property_hash[:name] = @resource.name

    self.dirty!
  end

  # Use the prefetched status to determine of the resource exists.
  #
  # This method is necessary for the provider to be ensurable
  #
  # @return [TrueClass || FalseClass]
  def exists?
    @property_hash[:ensure] and @property_hash[:ensure] == :present
  end

  # Update the property hash to mark this resource as absent for flushing
  #
  # This method is necessary for the provider to be ensurable
  def destroy
    @property_hash[:ensure] = :absent
    self.dirty!
  end

  # Mark the file associated with this resource as dirty
  def dirty!
    file = select_file
    self.class.dirty_file! file
  end


  # When processing on this resource is complete, trigger a flush on the file
  # that this resource belongs to.
  def flush
    self.class.flush_file(self.select_file)
  end

  def self.included(klass)
    klass.extend PuppetX::FileMapper::ClassMethods
    klass.mk_resource_methods
    klass.initvars
  end

  module ClassMethods

    attr_reader :mapped_files

    def initvars
      # Mapped_files: [Hash<filepath => Hash<:dirty => Bool, :filetype => Filetype>>]
      @mapped_files = Hash.new {|h, k| h[k] = {}}
      @failed       = false
      @all_providers = []
    end

    def failed?
      @failed
    end

    # Register all provider instances with the class
    #
    # In order to flush all provider instances to a given file, we need to be
    # able to track them all. When provider#flush is called and the file
    # associated with that provider instance is dirty, the file needs to be
    # flushed and all provider instances associated with that file will be
    # passed to self.flush_file
    def new(*args)
      obj = super
      @all_providers << obj
      obj
    end

    # Returns all instances of the provider using this mixin.
    #
    # @return [Array<Puppet::Provider>]
    def instances
      provider_hashes = load_all_providers_from_disk

      provider_hashes.map do |h|
        h.merge!({:provider => self.name})
        new(h)
      end

    rescue
      # If something failed while loading instances, mark the provider class
      # as failed and pass the exception along
      @failed = true
      raise
    end

    # Validate that the required methods are available.
    #
    # @raise Puppet::DevError if an expected method is unavailable
    def validate_class!
      required_class_hooks    = [:target_files, :parse_file]
      required_instance_hooks = [:select_file]

      required_class_hooks.each do |method|
        raise Puppet::DevError, "#{self} has not implemented `self.#{method}`" unless self.respond_to? method
      end

      required_instance_hooks.each do |method|
        raise Puppet::DevError, "#{self} has not implemented `##{method}`" unless self.method_defined? method
      end
    end

    # Reads all files from disk and returns an array of hashes representing
    # provider instances.
    #
    # @return [Array<Hash<String, Hash<Symbol, Object>>>]
    #   An array containing a set of hashes, keyed with a file path and values
    #   being a hash containg the state of the file and the filetype associated
    #   with it.
    #
    def load_all_providers_from_disk
      validate_class!

      # Retrieve a list of files to fetch, and cache a copy of a filetype
      # for each one
      target_files.each do |file|
        @mapped_files[file][:filetype] = Puppet::Util::FileType.filetype(:flat).new(file)
        @mapped_files[file][:dirty]    = false
      end

      # Read and parse each file.
      provider_hashes = []
      @mapped_files.each_pair do |filename, file_attrs|
        arr = parse_file(filename, file_attrs[:filetype].read)
        provider_hashes.concat arr
      end

      provider_hashes
    end

    # Match up all resources that have existing providers.
    #
    # Pass over all provider instances, and see if there is a resource with the
    # same namevar as a provider instance. If such a resource exists, set the
    # provider field of that resource to the existing provider.
    #
    # This is a hook method that will be called by Puppet::Transaction#prefetch
    #
    # @param [Hash<String, Puppet::Resource>] resources
    def prefetch(resources = {})

      # generate hash of {provider_name => provider}
      providers = instances.inject({}) do |hash, instance|
        hash[instance.name] = instance
        hash
      end

      # For each prefetched resource, try to match it to a provider
      resources.each_pair do |resource_name, resource|
        if provider = providers[resource_name]
          resource.provider = provider
        end
      end
    end

    # Generate attr_accessors for the properties, and have them mark the file
    # as modified if an attr_writer is called.
    # This is basically ripped off from ParsedFile
    def mk_resource_methods
      resource_type.validproperties.each do |attr|
        attr = symbolize(attr)

        # Generate the attr_reader method
        define_method(attr) do
          if @property_hash[attr]
            @property_hash[attr]
          elsif defined? @resource
            @resource.should(attr)
          end
        end

        # Generate the attr_writer and have it mark the resource as dirty when called
        define_method("#{attr}=") do |val|
          @property_hash[attr] = val
          self.dirty!
        end
      end
    end

    # Generate an array of providers that should be flushed to a specific file
    #
    # @param [String] filename The name of the file to find providers for
    #
    # @return [Array<Puppet::Provider>]
    def collect_providers_for_file(filename)
      @all_providers.select do |provider|
        provider.select_file == filename
      end
    end

    def dirty_file!(filename)
      @mapped_files[filename][:dirty] = true
    end

    # Flush all providers associated with the given file to disk.
    #
    # If the provider is in a failure state, the provider class will refuse to
    # flush any file, since we're in an unknown state.
    #
    # @param [String] filename The path of the file to be flushed
    def flush_file(filename)
      if failed?
        Puppet.error "#{self.name} is in an error state, refusing to flush file #{filename}"
        return
      end

      if @mapped_files[filename][:dirty]

        target_providers = collect_providers_for_file(filename)

        # XXX Perhaps don't raise an exception on this case.
        if target_providers.empty?
          raise Puppet::DevError, "#{self.name} was requested to flush file #{filename} but no provider instances are associated with it"
        end

        file_contents = self.format_file(filename, target_providers)

        # We have a dirty file and the new contents ready, back up the file and perform the flush.
        filetype = @mapped_files[filename][:filetype]
        # XXX CHECK FOR NIL
        filetype.backup
        filetype.write(file_contents)
      else
        Puppet.debug "#{self.name} was requested to flush the file #{filename}, but it was not marked as dirty - doing nothing."
      end
    rescue => e
      # If something failed during the flush process, mark the provider as
      # failed. There's not much we can do about any file that's already been
      # flushed but we can stop smashing things.
      @failed = true
      raise
    end
  end
end
