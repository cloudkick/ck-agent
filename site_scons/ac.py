import os

def CheckStructOffset(context, t1, includes, member):
  context.Message('Checking offsetof(%s, %s).... ' % (t1, member))
  source = """
"""+ includes +"""
#include <stdlib.h>
#include <stdio.h>

/**
 * Finding offsets of elements within structures.
 * Taken from the X code... they've sweated portability of this stuff
 * so we don't have to.  Sigh...
 * @param p_type pointer type name
 * @param field  data field within the structure pointed to
 * @return offset
 */

#if defined(CRAY) || (defined(__arm) && !defined(LINUX))
#ifdef __STDC__
#define APR_OFFSET(p_type,field) _Offsetof(p_type,field)
#else
#ifdef CRAY2
#define APR_OFFSET(p_type,field) \
        (sizeof(int)*((unsigned int)&(((p_type)NULL)->field)))

#else /* !CRAY2 */

#define APR_OFFSET(p_type,field) ((unsigned int)&(((p_type)NULL)->field))

#endif /* !CRAY2 */
#endif /* __STDC__ */
#else /* ! (CRAY || __arm) */

#define APR_OFFSET(p_type,field) \
        ((long) (((char *) (&(((p_type)NULL)->field))) - ((char *) NULL)))

#endif /* !CRAY */

/**
 * Finding offsets of elements within structures.
 * @param s_type structure type name
 * @param field  data field within the structure
 * @return offset
 */
#if defined(offsetof) && !defined(__cplusplus)
#define APR_OFFSETOF(s_type,field) offsetof(s_type,field)
#else
#define APR_OFFSETOF(s_type,field) APR_OFFSET(s_type*,field)
#endif

int main()
{
    printf("%d", (int)APR_OFFSETOF(""" + t1 + """, """+ member +"""));
    return 0;
}
  """
  result = context.TryRun(source, '.c')
  if (result[0] == 1):
    context.Result(result[1])
  else:
    context.Result("error, see config.log")
    return -1
  return int(result[1])

def CheckUname(context, args):
  prog = context.env.WhereIs("uname")
  context.Message("Checking %s %s ...." % (prog, args))
  output = context.sconf.confdir.File(os.path.basename(prog)+'.out') 
  node = context.sconf.env.Command(output, prog, [ [ prog, args, ">", "${TARGET}"] ]) 
  ok = context.sconf.BuildNodes(node) 
  if ok: 
    outputStr = output.get_contents().strip()
    context.Result(" "+ outputStr)
    return (1, outputStr)
  else:
    context.Result("error running uname")
    return (0, "")


def CheckDpkgArch(context):
  args = "-qDEB_BUILD_ARCH"
  prog = context.env.WhereIs("dpkg-architecture")
  if not prog:
    context.Message("Error: `dpkg-architecture` not found. Install dpkg-dev?")
    return (0, "")
  context.Message("Checking %s %s ...." % (prog, args))
  output = context.sconf.confdir.File(os.path.basename(prog)+'.out') 
  node = context.sconf.env.Command(output, prog, [ [ prog, args, ">", "${TARGET}"] ]) 
  ok = context.sconf.BuildNodes(node) 
  if ok: 
    outputStr = output.get_contents().strip()
    context.Result(" "+ outputStr)
    return (1, outputStr)
  else:
    context.Result("error running dpkg-architecture")
    return (0, "")

