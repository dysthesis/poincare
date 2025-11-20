use mlua::prelude::LuaFunction;
use nvim_oxi::{Result, mlua, print};

mod api;
mod cfg;

#[nvim_oxi::plugin]
fn poincare() -> Result<()> {
    cfg::options::options();
    Ok(())
}
