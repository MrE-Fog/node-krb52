k = require '../../build/Debug/krb5'
fs = require 'fs'


cleanup = (ctx, princ, ccache) ->
  if princ
    k.krb5_free_principal_sync ctx, princ
  if ccache
    k.krb5_cc_close ctx, ccache, (err) ->
      if ctx
        k.krb5_free_context_sync ctx
  else if ctx
    k.krb5_free_context_sync ctx


handle_error = (callback, err, ctx, princ, ccache) ->
  if !err
    return err
  err = k.krb5_get_error_message_sync(ctx, err)
  cleanup ctx, princ, ccache
  callback(new Error(err), { cc_path: null })


kinit = (options, callback) ->
  if !options.username || !options.realm
    console.log 'Please specify user and realm for kinit'
    return -1

  k.krb5_init_context (err, ctx) ->
    return handle_error(callback, err, ctx) if err

    k.krb5_build_principal ctx,
    options.realm.length,
    options.realm,
    options.username,
    (err, princ) ->
      return handle_error(callback, err, ctx, princ) if err

      k.krb5_cc_default ctx, (err, ccache) ->
        return handle_error(callback, err, ctx, princ, ccache) if err

        cc_path = k.krb5_cc_get_name_sync ctx, ccache
        fs.exists cc_path, (exists) ->
          create_cc = (create_cc_callback) ->
            if !exists
              k.krb5_cc_initialize ctx, ccache, princ, (err) ->
                return handle_error(callback, err, ctx, princ, ccache) if err
                create_cc_callback()
            else
              create_cc_callback()

          get_creds_password = () ->
            k.krb5_get_init_creds_password ctx, princ, options.password, (err, creds) ->
              return handle_error(callback, err, ctx, princ, ccache) if err
              store_creds creds

          get_creds_keytab = () ->
            k.krb5_kt_resolve ctx, options.keytab, (err, kt) ->
              return handle_error(callback, err, ctx, princ, ccache) if err
              k.krb5_get_init_creds_keytab ctx, princ, kt, 0, (err, creds) ->
                return handle_error(callback, err, ctx, princ, ccache) if err
                store_creds creds
                  
          store_creds = (creds) ->
            k.krb5_cc_store_cred ctx, ccache, creds, (err) ->
              return handle_error(callback, err, ctx, princ, ccache) if err
              cc_path = k.krb5_cc_get_name_sync ctx, ccache
              callback 0, { cc_path }

          create_cc if options.password then get_creds_password else get_creds_keytab
          return

spnego = (options, callback) ->
  service_principal_or_fqdn = null
  service_principal_or_fqdn ?= options.service_principal
  service_principal_or_fqdn ?= options.service_fqdn
  return callback Error 'Missing property "service_principal" or "service_fqdn"' unless service_principal_or_fqdn
  service_principal_or_fqdn = "HTTP@#{service_principal_or_fqdn}" unless /HTTP[@\/]/.test service_principal_or_fqdn

  k.generate_spnego_token service_principal_or_fqdn, (gss_err, gss_minor, token) ->
    callback(gss_err, token)

module.exports = {
  kinit
  spnego
}