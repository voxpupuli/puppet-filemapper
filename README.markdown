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

This mixin does just that. You define two methods: `self.parse_file` and
`self.format_resources`. The former takes an object that responds to `#each` and
returns an array of providers; the latter takes an array of providers and
produces an object that responds to `#each`. Everything else is handled by the
FileMapper mixin, such as prefetching, the instances method, single pass file
flushing, all that neat stuff.

You figure out how to parse and write the file, and this will do the rest.
