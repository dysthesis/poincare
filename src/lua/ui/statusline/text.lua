-- Statusline directives are authored by components; buffer data is literal.
return function(value)
  return (value:gsub("%%", "%%%%"))
end
