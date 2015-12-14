Langkit
=======

Dependencies
------------

To use Langkit:

- Quex version 0.64.8 - http://sourceforge.net/projects/quex/files/HISTORY/0.64
  Follow the installation guide in the quex `README`
- The mako template system for Python (see `REQUIREMENTS.dev`)
- Clang-format

Install
-------

There is no proper distribution for the langkit Python package, so just add the
top-level langkit directory to your `PYTHONPATH` in order to use it. Note that
this directory is self-contained, so you can copy it somewhere else.

Testing
-------

There is currently no testsuite dedicated to Langkit. Yeah, it's bad! But we
plan to add one at some point.

Documentation
-------------

The developer and user's documentation for Langkit is in `langkit/doc`. You can
consult it as a text files or you can build it. For instance, to generate HTML
documents, run from the top directory:

    $ make -C langkit/doc html

And then open the following file in your favorite browser:

    langkit/doc/_build/html/index.html

Bootstrapping a new language engine
-----------------------------------

Nothing is more simple than getting an initial project skeleton to work on a new
language engine. Imagine you want to create an engine for the Foo language, run
from the top-level directory:

    $ python langkit/create-project.py Foo

And then have a look at the created `foo` directory: you have minimal lexers and
parsers and a `manage.py` script you can use to build this new engine:

    $ python foo/manage.py make

Here you are!

Developer tools
---------------

Langkit uses mako templates generating Ada, C and Python code. This can be hard
to read. To ease development, Vim syntax files are available under the `utils`
directory (see `makoada.vim`, `makocpp.vim`). Install them in your
`$HOME/.vim/syntax` directory to get automatic highlighting of the template
files.