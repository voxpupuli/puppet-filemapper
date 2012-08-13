
# Forward declaration
module PuppetX; end

module PuppetX::FileMapper

  class << self

    attr_reader :failed

    def initvars
      @mapped_files = {}
      @failed       = false
    end

    initvars

    # Returns all instances of the provider including this class.
    #
    # @return [Array<Puppet::Provider>]
    def instances
      # Validate that the methods required for prefetching are available
      [:files_to_prefetch, :prefetch_file].each do |method|
        unless self.respond_to? method
          raise NotImplementedError, "#{self.name} has not implemented `self.#{method}`"
        end
      end

      # Retrieve a list of files to prefetch, and cache a copy of a filetype
      # for each one
      files_to_prefetch.each do |file|
        @mapped_files[file] = Puppet::Util::FileType.filetype(:flat).new(file)
      end

      provider_hashes = []
      @mapped_files.each_pair do |filename, filetype|
        provider_hashes.concat(prefetch_file(filename, filetype.read))
      end

      # Add the provider name to each one of the new provider instances
      # and then generate them.
      provider_hashes.map do |h|
        h.merge!({:provider => self.name})
        new(h)
      end

    rescue
      # If something failed while loading instances, mark the provider class
      # as failed and pass the exception along
      self.failed = true
      raise
    end

    # Pass over all provider instances, and see if there is a resource with the
    # same namevar as a provider instance. If such a resource exists, set the
    # provider field of that resource to the existing provider.
    def prefetch(resources = {})

      # generate hash of {provider_name => provider}
      providers = instances.inject({}) do |hash, instance|
        hash[instance.name] = instance
        hash
      end

      # For each prefetched resource, try to match it to a provider
      resources.each do |resource_name, resource|
        if provider = providers[resource_name]
          resource.provider = provider
        end
      end

      # Generate default providers for resources that don't exist on disk
      # FIXME this won't work with composite namevars or types whose namevar
      # is not 'name'
      resources.values.select {|resource| resource.provider.nil? }.each do |resource|
        resource.provider = new(:name => resource.name, :provider => name, :ensure => :absent)
      end

      nil
    end
  end
end
