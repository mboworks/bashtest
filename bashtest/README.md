# mboworks_bashtest//bashtest

Bashtest provides `sh_test` wrapper that simplifies the creation of shell tests.


  * bashtest:bashtest, bashtest/bashtest.sh
  * sh_library `bashtest.sh` which provides a test runner for complex shell tests involving golden files that provides built-in golden update functionality (see `bazel run //bashtest:bashtest_help`).
    * status helper `test_has_error`: Returns whether a test function has had an expectation error. This is reset for every test function.
    * status helper `test_has_failed_tests`: Returns whether a test program had previous failing test functions.
    * expectation `expect_eq` "\${LHS}" "\${RHS}": Asserts that two strings are the same.
    * expectation `expect_ne` "\${LHS}" "\${RHS}": Asserts that two strings are different.
    * expectation `expect_files_eq` "\${LHS}" "\${RHS}": Asserts that two file are the same (supports golden updates).
    * expectation `expect_contains` "\${EXPECTED}" "\${ARRAY[@]}": Assert that one string is present in an array.
    * expectation `expect_not_contains` "\${EXPECTED}" "\${ARRAY[@]}": Assert that one string is not present in an array.
    * expectation `expect_output_contains` "\${SUBSTRING}" "\${TEXT}": Assert that a text contains a literal substring.
    * expectation `expect_output_not_contains` "\${SUBSTRING}" "\${TEXT}": Assert that a text does not contain a literal substring.
    * expectation `expect_matches` "\${REGEX}" "\${TEXT}": Assert that a text matches an extended regular expression (bash built-in; `^`/`$` anchor the whole text).
    * expectation `expect_not_matches` "\${REGEX}" "\${TEXT}": Assert that a text does not match an extended regular expression.
    * expectation `expect_pcre_matches` "\${REGEX}" "\${TEXT}": Assert that a text matches a Perl Compatible Regular Expression (requires an external PCRE tool).
    * expectation `expect_pcre_not_matches` "\${REGEX}" "\${TEXT}": Assert that a text does not match a Perl Compatible Regular Expression.
    * special test function `test::test_init`: If present, then this function runs first! Tests will only be executed if it succeeds.
    * special test function `test::test_done`: If present, then this function runs last!
