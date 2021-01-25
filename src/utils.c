#include "utils.h"

void bail_if(int err, const char *what){
  if (err) {
    const git_error *info = giterr_last();
    SEXP code = PROTECT(Rf_ScalarInteger(err));
    SEXP kclass = PROTECT(Rf_ScalarInteger(info ? info->klass : NA_INTEGER));
    SEXP message = PROTECT(safe_string(info ? info->message : "Unknown error message"));
    SEXP wheregit = PROTECT(safe_string(what));
    SEXP expr = PROTECT(Rf_install("raise_libgit2_error"));
    SEXP call = PROTECT(Rf_lang5(expr, code, message, wheregit, kclass));
    Rf_eval(call, R_FindNamespace(Rf_mkString("gert")));
    UNPROTECT(6);
    Rf_error("Failed to raise gert S3 error (%s)", info->message);
  }
}

void warn_last_msg(){
  const git_error *info = giterr_last();
  if (info){
    Rf_warningcall_immediate(R_NilValue, "libgit2 warning: %s (%d)\n", info->message, info->klass);
  }
}

void bail_if_null(void * ptr, const char * what){
  if(!ptr)
    bail_if(-1, what);
}

#ifndef GIT_OBJECT_COMMIT
#define GIT_OBJECT_COMMIT GIT_OBJ_COMMIT
#endif

git_object * resolve_refish(SEXP string, git_repository *repo){
  if(!Rf_isString(string) || !Rf_length(string))
    Rf_error("Reference is not a string");
  const char *str = CHAR(STRING_ELT(string, 0));
  git_reference *ref = NULL;
  git_object *obj = NULL;
  if(git_reference_dwim(&ref, repo, str) == GIT_OK){
    if(git_reference_peel(&obj, ref, GIT_OBJECT_COMMIT) == GIT_OK){
      git_reference_free(ref);
      return obj;
    }
  }
  if(git_revparse_single(&obj, repo, str) == GIT_OK){
    if(git_object_type(obj) == GIT_OBJECT_COMMIT)
      return obj;
    git_object *peeled = NULL;
    if(git_object_peel(&peeled, obj, GIT_OBJECT_COMMIT) == GIT_OK){
      git_object_free(obj);
      return peeled;
    }
    const char *type = git_object_type2string(git_object_type(obj));
    git_object_free(obj);
    Rf_error("Reference is a %s and does not point to a commit: %s", type, str);
  } else {
    Rf_error("Failed to find git reference '%s'", str);
  }
}

git_commit *ref_to_commit(SEXP ref, git_repository *repo){
  git_commit *commit = NULL;
  git_object *revision = resolve_refish(ref, repo);
  bail_if(git_commit_lookup(&commit, repo, git_object_id(revision)), "git_commit_lookup");
  git_object_free(revision);
  return commit;
}

SEXP safe_string(const char *x){
  return Rf_ScalarString(safe_char(x));
}

SEXP string_or_null(const char *x){
  if(x == NULL)
    return R_NilValue;
  return Rf_mkString(x);
}

SEXP safe_char(const char *x){
  if(x == NULL)
    return NA_STRING;
  return Rf_mkCharCE(x, CE_UTF8);
}

SEXP make_strvec(int n, ...){
  va_list args;
  va_start(args, n);
  SEXP out = PROTECT(Rf_allocVector(STRSXP, n));
  for (int i = 0; i < n; i++)  {
    const char *val = va_arg(args, const char *);
    SET_STRING_ELT(out, i, safe_char(val));
  }
  va_end(args);
  UNPROTECT(1);
  return out;
}

/* The input SEXPS must be protected beforehand */
SEXP build_list_internal(int n, ...){
  va_list args;
  va_start(args, n);
  SEXP names = PROTECT(Rf_allocVector(STRSXP, n));
  SEXP vec = PROTECT(Rf_allocVector(VECSXP, n));
  for (int i = 0; i < n; i++)  {
    SET_STRING_ELT(names, i, safe_char(va_arg(args, const char *)));
    SET_VECTOR_ELT(vec, i, va_arg(args, SEXP));
  }
  va_end(args);
  Rf_setAttrib(vec, R_NamesSymbol, names);
  UNPROTECT(2);
  return vec;
}

SEXP list_to_tibble(SEXP df){
  PROTECT(df);
  int nrows = Rf_length(df) ? Rf_length(VECTOR_ELT(df, 0)) : 0;
  SEXP rownames = PROTECT(Rf_allocVector(INTSXP, nrows));
  for(int j = 0; j < nrows; j++)
    INTEGER(rownames)[j] = j+1;
  Rf_setAttrib(df, R_RowNamesSymbol, rownames);
  Rf_setAttrib(df, R_ClassSymbol, make_strvec(3, "tbl_df", "tbl", "data.frame"));
  UNPROTECT(2);
  return df;
}

static int checkout_notify_cb(git_checkout_notify_t why, const char *path, const git_diff_file *baseline,
                              const git_diff_file *target, const git_diff_file *workdir, void *payload){
  //git_checkout_options *opts = payload;
  if(why == GIT_CHECKOUT_NOTIFY_CONFLICT){
    Rf_warningcall_immediate(R_NilValue, "Your local changes to the following file would be overwritten by checkout: %s\nUse force = TRUE to checkout anyway.", path);
  }
  return 0;
}

void set_checkout_notify_cb(git_checkout_options *opts){
  opts->notify_cb = checkout_notify_cb;
  opts->notify_flags = GIT_CHECKOUT_NOTIFY_CONFLICT;
  opts->notify_payload = opts;
}

/* Wrappers with hardcoded unprotect(n) to please rchk */
#define XP(i) const char * xna##i, SEXP xnb##i
#define XA(i) xna##i, xnb##i

inline SEXP build_list1(XP(1)){
  SEXP out = build_list_internal(1, XA(1));
  UNPROTECT(1);
  return out;
}

inline SEXP build_list2(XP(1), XP(2)){
  SEXP out = build_list_internal(2, XA(1), XA(2));
  UNPROTECT(2);
  return out;
}

inline SEXP build_list3(XP(1), XP(2), XP(3)){
  SEXP out = build_list_internal(3, XA(1), XA(2), XA(3));
  UNPROTECT(3);
  return out;
}

inline SEXP build_list4(XP(1), XP(2), XP(3), XP(4)){
  SEXP out = build_list_internal(4, XA(1), XA(2), XA(3), XA(4));
  UNPROTECT(4);
  return out;
}

inline SEXP build_list5(XP(1), XP(2), XP(3), XP(4), XP(5)){
  SEXP out = build_list_internal(5, XA(1), XA(2), XA(3), XA(4), XA(5));
  UNPROTECT(5);
  return out;
}

inline SEXP build_list6(XP(1), XP(2), XP(3), XP(4), XP(5), XP(6)){
  SEXP out = build_list_internal(6, XA(1), XA(2), XA(3), XA(4), XA(5), XA(6));
  UNPROTECT(6);
  return out;
}

inline SEXP build_list7(XP(1), XP(2), XP(3), XP(4), XP(5), XP(6), XP(7)){
  SEXP out = build_list_internal(7, XA(1), XA(2), XA(3), XA(4), XA(5), XA(6), XA(7));
  UNPROTECT(7);
  return out;
}

inline SEXP build_list8(XP(1), XP(2), XP(3), XP(4), XP(5), XP(6), XP(7), XP(8)){
  SEXP out = build_list_internal(8, XA(1), XA(2), XA(3), XA(4), XA(5), XA(6), XA(7), XA(8));
  UNPROTECT(8);
  return out;
}
