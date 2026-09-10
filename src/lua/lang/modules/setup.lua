return function(lang, setup)
  if type(setup) == "function" then
    setup(lang)
    return
  end

  for _, f in ipairs(setup) do
    f(lang)
  end
end
