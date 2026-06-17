from flask import Blueprint, flash, redirect, render_template, request, session, url_for

from routes.auth import execute_with_result_sets, login_required


empleado_bp = Blueprint("empleado", __name__)


def obtener_id_empleado_actual():
    if session.get("tipo_usuario") == 1:
        return session.get("id_empleado_impersonado")

    return session.get("id_empleado")


def obtener_id_empleado(id_usuario):
    sql = """
        SELECT e.IdEmpleado
        FROM dbo.Empleado AS e
        WHERE (e.IdUsuario = ?)
          AND (e.Activo = 1);
    """
    result_sets, _ = execute_with_result_sets(sql, [id_usuario])
    if not result_sets or not result_sets[0]:
        return None

    return result_sets[0][0]["IdEmpleado"]


def consultar_planilla_semanal(id_empleado, id_semana=None):
    sql = """
        DECLARE @outResultCode INT;

        EXEC dbo.sp_ConsultarPlanillaSemanal
            @inIdEmpleado = ?
          , @inIdSemanaPlanilla = ?
          , @outResultCode = @outResultCode OUTPUT;

        SELECT @outResultCode AS ResultCode;
    """
    return execute_with_result_sets(sql, [id_empleado, id_semana])


def consultar_deducciones_semana(id_empleado, id_semana=None):
    sql = """
        DECLARE @outResultCode INT;

        EXEC dbo.sp_ConsultarDetalleDeduccionesSemana
            @inIdEmpleado = ?
          , @inIdSemanaPlanilla = ?
          , @outResultCode = @outResultCode OUTPUT;

        SELECT @outResultCode AS ResultCode;
    """
    return execute_with_result_sets(sql, [id_empleado, id_semana])


def consultar_horas_semana(id_empleado, id_semana=None):
    sql = """
        DECLARE @outResultCode INT;

        EXEC dbo.sp_ConsultarDetalleHorasSemana
            @inIdEmpleado = ?
          , @inIdSemanaPlanilla = ?
          , @outResultCode = @outResultCode OUTPUT;

        SELECT @outResultCode AS ResultCode;
    """
    return execute_with_result_sets(sql, [id_empleado, id_semana])


def consultar_planilla_mensual(id_empleado, id_mes=None):
    sql = """
        DECLARE @outResultCode INT;

        EXEC dbo.sp_ConsultarPlanillaMensual
            @inIdEmpleado = ?
          , @inIdMesPlanilla = ?
          , @outResultCode = @outResultCode OUTPUT;

        SELECT @outResultCode AS ResultCode;
    """
    return execute_with_result_sets(sql, [id_empleado, id_mes])


def consultar_deducciones_mes(id_empleado, id_mes=None):
    sql = """
        DECLARE @outResultCode INT;

        EXEC dbo.sp_ConsultarDetalleDeduccionesMes
            @inIdEmpleado = ?
          , @inIdMesPlanilla = ?
          , @outResultCode = @outResultCode OUTPUT;

        SELECT @outResultCode AS ResultCode;
    """
    return execute_with_result_sets(sql, [id_empleado, id_mes])


@empleado_bp.route("/planilla-semanal")
@login_required
def planilla_semanal():
    id_semana = request.args.get("id_semana", type=int)
    id_empleado = obtener_id_empleado_actual()
    planillas = []
    deducciones = []
    horas = []
    result_code = None

    try:
        if id_empleado is None:
            if session.get("tipo_usuario") == 1:
                flash("Seleccione un empleado para impersonar.", "error")
                return redirect(url_for("admin.empleados"))

            id_empleado = obtener_id_empleado(session.get("id_usuario"))
            session["id_empleado"] = id_empleado

        resumen_sets, resumen_output = consultar_planilla_semanal(id_empleado, id_semana)
        deducciones_sets, _ = consultar_deducciones_semana(id_empleado, id_semana)
        horas_sets, _ = consultar_horas_semana(id_empleado, id_semana)
        planillas = resumen_sets[0] if resumen_sets else []
        deducciones = deducciones_sets[0] if deducciones_sets else []
        horas = horas_sets[0] if horas_sets else []
        result_code = resumen_output.get("ResultCode")
    except Exception as exc:
        flash(str(exc), "error")

    return render_template(
        "empleado/planilla_semanal.html",
        id_empleado=id_empleado,
        id_semana=id_semana,
        planillas=planillas,
        deducciones=deducciones,
        horas=horas,
        result_code=result_code,
    )


@empleado_bp.route("/planilla-mensual")
@login_required
def planilla_mensual():
    id_mes = request.args.get("id_mes", type=int)
    id_empleado = obtener_id_empleado_actual()
    planillas = []
    deducciones = []
    result_code = None

    try:
        if id_empleado is None:
            if session.get("tipo_usuario") == 1:
                flash("Seleccione un empleado para impersonar.", "error")
                return redirect(url_for("admin.empleados"))

            id_empleado = obtener_id_empleado(session.get("id_usuario"))
            session["id_empleado"] = id_empleado

        resumen_sets, resumen_output = consultar_planilla_mensual(id_empleado, id_mes)
        deducciones_sets, _ = consultar_deducciones_mes(id_empleado, id_mes)
        planillas = resumen_sets[0] if resumen_sets else []
        deducciones = deducciones_sets[0] if deducciones_sets else []
        result_code = resumen_output.get("ResultCode")
    except Exception as exc:
        flash(str(exc), "error")

    return render_template(
        "empleado/planilla_mensual.html",
        id_empleado=id_empleado,
        id_mes=id_mes,
        planillas=planillas,
        deducciones=deducciones,
        result_code=result_code,
    )
