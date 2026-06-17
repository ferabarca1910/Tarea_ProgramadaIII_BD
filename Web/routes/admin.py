from flask import Blueprint, flash, render_template, request

from routes.auth import admin_required, execute_with_result_sets


admin_bp = Blueprint("admin", __name__)


def listar_empleados(nombre=None, documento=None):
    sql = """
        DECLARE @outResultCode INT;

        EXEC dbo.sp_ListarEmpleadosConFiltro
            @inNombre = ?
          , @inValorDocumento = ?
          , @inSoloActivos = 1
          , @outResultCode = @outResultCode OUTPUT;

        SELECT @outResultCode AS ResultCode;
    """
    result_sets, output = execute_with_result_sets(sql, [nombre, documento])
    empleados = result_sets[0] if result_sets else []
    return empleados, output.get("ResultCode")


@admin_bp.route("/empleados")
@admin_required
def empleados():
    nombre = request.args.get("nombre") or None
    documento = request.args.get("documento") or None
    empleados_data = []
    result_code = None

    try:
        empleados_data, result_code = listar_empleados(nombre, documento)
    except Exception as exc:
        flash(str(exc), "error")

    return render_template(
        "admin/empleados.html",
        empleados=empleados_data,
        result_code=result_code,
        nombre=nombre or "",
        documento=documento or "",
    )
