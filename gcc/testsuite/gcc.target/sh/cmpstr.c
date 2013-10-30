/* Check that the __builtin_strcmp function is inlined with cmp/str
   when optimizing for speed.  */
/* { dg-do compile { target "sh*-*-*" } } */
/* { dg-options "-O2" } */
/* { dg-skip-if "" { "sh*-*-*" } { "-m5*" } { "" } } */
/* { dg-final { scan-assembler-not "jmp" } } */
/* { dg-final { scan-assembler-times "cmp/str" 3 } } */
/* { dg-final { scan-assembler-times "tst\t#3" 2 } } */

test00 (const char *s1, const char *s2)
{
  return __builtin_strcmp (s1, s2);
}

/* NB: This might change as further optimisation might detect the
   max length and fallback to cmpstrn.  */
test01(const char *s2)
{
  return __builtin_strcmp ("abc", s2);
}

/* Check that no test for alignment is needed.  */
test03(const char *s1, const char *s2)
{
  return __builtin_strcmp (__builtin_assume_aligned (s1, 4),
			   __builtin_assume_aligned (s2, 4));
}
