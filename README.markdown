Puppet FileMapper
=================

Synopsis
--------

Map files to resources and back with this handy dandy mixin!

Description
-----------

Things that are harder than they should be:

  * Acquiring a pet monkey
  * Getting anywhere in Los Angeles
  * Understanding the ParsedFile provider
  * Writing Puppet providers that directly manipulate files

The solution for this is to completely bypass parsing in any sort of base
provider, and delegate the role of parsing and generating to including classes.

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

### `self.format_file(filename, providers)`

This should take two values, a string containing the file name to be flushed,
and an array of providers that should be flushed to this file. It should return
a string containing the contents of the file to be written.
