Puppet FileMapper
=================

Synopsis
--------

Map files to resources and back with this handy dandy mixin!

Description
-----------

A common challenge in Puppet is managing a set of resources in files to Puppet
resources. The ParsedFile provider can handle some of these cases, but it has
limitations. If the files are not record based, it's very difficult to use
existing constructs to parse the file.

The solution for this is to completely bypass parsing in any sort of base
provider, and hand that over entirely to the including/inheriting class.

You figure out how to parse and write the file, and this will do the rest.

Implementation requirements
---------------------------

To use this mixin, you need to define a class that defines the following
methods.

### `self.target_files`

This should return an array of filenames specifying which files should be
prefetched.

### `self.parse_file(filename, file_contents)`

This should take two values, a string containing the file name, and a string
containing the contents of the file. It should return an array of hashes,
where each hash represents {property => value} pairs.

### `select_file`

This is a provider instance method. It should return a string containing the
filename that the provider should be flushed to.

### `self.flush_file(filename, providers)`

This should take two values, a string containing the file name to be flushed,
and an array of providers that should be flushed to this file. It should return
a string containing the contents of the file to be written.

### (Optional) `self.header`

This method should return a string containing a file header. If no such method
is defined then it will be ignored.
