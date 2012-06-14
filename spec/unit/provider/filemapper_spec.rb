require 'puppet/provider/filemapper'

describe Puppet::Provider::FileMapper do
  describe ".instances" do
    # This set of tests should be split out and targeted against the
    # isomorphism mixin

    it "should create a provider for each discovered interface" do
      @filetype.expects(:read).returns(fixture_data('single_interface_dhcp'))
      providers = @provider_class.instances
      providers.map(&:name).sort.should == ["eth0", "lo"]
    end

    it "should copy the interface attributes into the provider attributes" do
      @filetype.expects(:read).returns(fixture_data('single_interface_dhcp'))
      providers = @provider_class.instances
      eth0_provider = providers.find {|prov| prov.name == "eth0"}
      lo_provider   = providers.find {|prov| prov.name == "lo"}


      eth0_provider.family.should == "inet"
      eth0_provider.method.should == "dhcp"
      eth0_provider.options.should == { :"allow-hotplug" => true }

      lo_provider.family.should == "inet"
      lo_provider.method.should == "loopback"
      lo_provider.onboot.should == :true
      lo_provider.options.should be_empty
    end
  end

  describe ".prefetch" do
    # This set of tests should be split out and targeted against the
    # isomorphism mixin

    it "should match resources to providers whose names match" do

      @filetype.stubs(:read).returns(fixture_data('single_interface_dhcp'))

      lo_resource   = mock 'lo_resource'
      lo_resource.stubs(:name).returns("lo")
      eth0_resource = mock 'eth0_resource'
      eth0_resource.stubs(:name).returns("eth0")

      lo_provider = stub 'lo_provider', :name => "lo"
      eth0_provider = stub 'eth0_provider', :name => "eth0"

      @provider_class.stubs(:instances).returns [lo_provider, eth0_provider]

      lo_resource.expects(:provider=).with(lo_provider)
      eth0_resource.expects(:provider=).with(eth0_provider)
      lo_resource.expects(:provider).returns(lo_provider)
      eth0_resource.stubs(:provider).returns(eth0_provider)

      @provider_class.prefetch("eth0" => eth0_resource, "lo" => lo_resource)
    end

    it "should create a new absent provider for resources not on disk"
  end

  describe ".flush" do
    # This set of tests should be split out and targeted against the
    # isomorphism mixin

    before do
      @filetype.stubs(:backup)
      @filetype.stubs(:write)

      @provider_class.stubs(:needs_flush).returns true
    end

    it "should add interfaces that do not exist" do
      eth0 = @provider_class.new
      eth0.expects(:ensure).returns :present

      @provider_class.expects(:format_resources).with([eth0]).returns ["yep"]
      @provider_class.flush
    end

    it "should remove interfaces that do exist whose ensure is absent" do
      eth1 = @provider_class.new
      eth1.expects(:ensure).returns :absent

      @provider_class.expects(:format_resources).with([]).returns ["yep"]
      @provider_class.flush
    end

    it "should flush interfaces that were modified" do
      @provider_class.expects(:needs_flush=).with(true)

      eth0 = @provider_class.new
      eth0.family = :inet6

      @provider_class.flush
    end

    it "should not modify unmanaged interfaces"

    it "should back up the file if changes are made" do
      @filetype.unstub(:backup)
      @filetype.expects(:backup)

      eth0 = @provider_class.new
      eth0.stubs(:ensure).returns :present

      @provider_class.expects(:format_resources).with([eth0]).returns ["yep"]
      @provider_class.flush
    end

    it "should not flush if the interfaces file is malformed"
  end
end
