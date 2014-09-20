chanstats
=========

A simple script for estimating posts per hour measure for any board on
any given chan.


Supported engines
-----------------

* 4chan API (older version, where pagination starts with 0)
  * Known to work with vichan and Tinyboard
* Mitsuba / Yotsuba (4chan, Karachan)
* Tinyboard / vichan (when 4chan api is disabled)
* Northboard (point the script at the overboard)
* Desuchan (Krautchan)
* Kusaba (Kusaba X, 7chan)
* 420chan


Execution modes
---------------

    $ ./stat.rb pl

Makes statistics for polish chans and outputs them in HTML format.

    $ ./stat.rb v

Makes statistics for popular 8chan boards and their 4chan equivalents.

    $ ./stat.rb v json

Same as above, but outputs them in a JSON format.


JSON format
-----------

This one is made to facilitate statistics development. When run in this
mode, the script creates a history/[unixtimestamp].json file. The
structure being output is as follows:

    [
      ["http://int.vichan.net/b/", 4.4332465456],
      ["http://int.vichan.net/am/", 2.2343244134],
      ["http://int.vichan.net/int/", 3.141592654]
    ]

The first field is obviously board location. The second one is a
posts per *second* measure.


Installation
------------

You need Ruby 1.9 or later (2.0 recommended), Unix machine and a C
development kit (gcc, glibc-devel, ...).
Run the following to install all dependencies of the script:

    $ bundle install


Licensing
---------

Licensed under a MIT license.
