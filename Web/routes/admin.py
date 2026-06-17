from flask import Blueprint, flash, redirect, render_template, request, session, url_for

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


def obtener_empleado(id_empleado):
    sql = """
        DECLARE @outResultCode INT;

        EXEC dbo.sp_ObtenerEmpleado
            @inIdEmpleado = ?
          , @outResultCode = @outResultCode OUTPUT;

        SELECT @outResultCode AS ResultCode;
    """
    result_sets, output = execute_with_result_sets(sql, [id_empleado])
    empleados = result_sets[0] if result_sets else []
    empleado = empleados[0] if empleados else None
    return empleado, output.get("ResultCode")


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


@admin_bp.route("/impersonar/<int:id_empleado>", methods=["POST"])
@admin_required
def impersonar_empleado(id_empleado):
    try:
        empleado, result_code = obtener_empleado(id_empleado)
    except Exception as exc:
        flash(str(exc), "error")
        return redirect(url_for("admin.empleados"))

    if result_code != 0 or empleado is None:
        flash(f"No se pudo impersonar el empleado. ResultCode: {result_code}", "error")
        return redirect(url_for("admin.empleados"))

    session["id_empleado_impersonado"] = empleado["IdEmpleado"]
    session["nombre_empleado_impersonado"] = empleado["Nombre"]
    flash(f"Impersonando a {empleado['Nombre']}.", "info")
    return redirect(url_for("empleado.planilla_semanal"))


@admin_bp.route("/regresar-impersonacion")
@admin_required
def regresar_impersonacion():
    session.pop("id_empleado_impersonado", None)
    session.pop("nombre_empleado_impersonado", None)
    flash("Regresaste al modo administrador.", "info")
    return redirect(url_for("admin.empleados"))
