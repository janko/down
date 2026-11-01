D = Steep::Diagnostic

# Signatures are written inline in lib/ and generated into sig/generated/ with
# `rake rbs:generate` (rbs-inline). Steep checks lib/ against those signatures,
# which are the same ones shipped with the gem. sig/_patches/ fixes gaps in
# third-party signatures; RBS skips directories starting with `_` when loading
# the gem as a library, so the patches don't reach gem users.
target :lib do
  signature "sig"

  check "lib"

  configure_code_diagnostics(D::Ruby.strict)
end
