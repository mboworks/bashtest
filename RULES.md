Some rules for the code layout and its development.

* Everything is under Apache 2 license, see file `LICENSE`.
* All sources must be unix-text files: https://en.wikipedia.org/wiki/Text_file
  * Lines end in {LF}.
  * The files are either empty or end in {LF}.
* All exported library code is in the directory 'bashtest'.
* No namespace may be named 'internal'.
* All public / exported code must:
  * be tested,
  * have documentation.
* API changes that are not backwards compatible should not occur in minor version changes.
* Undocumented and private/internal APIs may be changed in any way at any time.
