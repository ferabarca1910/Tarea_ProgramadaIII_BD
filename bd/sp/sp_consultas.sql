
USE PlanillaObrera;
GO

IF OBJECT_ID('sp_Login', 'P') IS NOT NULL DROP PROCEDURE sp_Login;
GO
CREATE PROCEDURE sp_Login
    @Username   VARCHAR(50),
    @Password   VARCHAR(255),
    @IPOrigen   VARCHAR(45),
    @IdUsuario  INT OUTPUT,
    @Tipo TINYINT OUTPUT,
    @Exitoso    BIT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
 
    SELECT
        @IdUsuario   = IdUsuario,
        @Tipo = Tipo
    FROM dbo.Usuario
    WHERE Username = @Username
      AND PasswordHash = @Password  
      AND Activo = 1;
 
    IF @IdUsuario IS NOT NULL
    BEGIN
        SET @Exitoso = 1;
        EXEC sp_RegistrarEvento @IdUsuario, 1, @IPOrigen,
            N'{"username":"' + @Username + '","resultado":"exitoso"}';
    END
    ELSE
    BEGIN
        SET @Exitoso = 0;

        EXEC sp_RegistrarEvento 1, 2, @IPOrigen,
            N'{"username":"' + @Username + '","resultado":"fallido"}';
    END;
END;
GO
 
IF OBJECT_ID('sp_Logout', 'P') IS NOT NULL DROP PROCEDURE sp_Logout;
GO
CREATE PROCEDURE sp_Logout
    @IdUsuario  INT,
    @IPOrigen   VARCHAR(45)
AS
BEGIN
    SET NOCOUNT ON;
    EXEC sp_RegistrarEvento @IdUsuario, 11, @IPOrigen, NULL;
END;
GO
 
IF OBJECT_ID('sp_ListarEmpleados', 'P') IS NOT NULL DROP PROCEDURE sp_ListarEmpleados;
GO
CREATE PROCEDURE sp_ListarEmpleados
    @IdUsuario  INT,
    @IPOrigen   VARCHAR(45),
    @Filtro     VARCHAR(150) = NULL   
AS
BEGIN
    SET NOCOUNT ON;
 
    SELECT
        e.IdEmpleado,
        e.Nombre,
        p.Nombre                    AS NombrePuesto,
        e.ValorDocumentoIdentidad,
        e.FechaIngreso
    FROM dbo.Empleado e
    INNER JOIN dbo.Puesto p ON e.IdPuesto = p.IdPuesto
    WHERE e.Activo = 1
      AND (@Filtro IS NULL OR e.Nombre LIKE '%' + @Filtro + '%')
    ORDER BY e.Nombre;
 
    IF @Filtro IS NULL
        EXEC sp_RegistrarEvento @IdUsuario, 17, @IPOrigen, NULL;                         
    ELSE
        EXEC sp_RegistrarEvento @IdUsuario, 11, @IPOrigen,
            N'{"filtro":"' + @Filtro + '"}';                                             
END;
GO

IF OBJECT_ID('sp_ConsultarPlanillaSemanal', 'P') IS NOT NULL DROP PROCEDURE sp_ConsultarPlanillaSemanal;
GO
CREATE PROCEDURE sp_ConsultarPlanillaSemanal
    @IdEmpleado     INT,
    @IdUsuario      INT,
    @IPOrigen       VARCHAR(45),
    @TopSemanas     INT = 10
AS
BEGIN
    SET NOCOUNT ON;
 

    SELECT TOP (@TopSemanas)
        sp.IdSemanaPlanilla,
        sp.FechaInicio,
        sp.FechaFin,
        pse.IdPlanillaSemXEmpleado,
        pse.SalarioBruto,
        pse.TotalDeducciones,
        pse.SalarioNeto,
        pse.HorasOrdinarias,
        pse.HorasExtraNormales,
        pse.HorasExtraDobles
    FROM dbo.PlanillaSemXEmpleado pse
    INNER JOIN dbo.SemanaPlanilla sp ON pse.IdSemanaPlanilla = sp.IdSemanaPlanilla
    WHERE pse.IdEmpleado = @IdEmpleado
    ORDER BY sp.FechaInicio DESC;
 
    DECLARE @params NVARCHAR(200) = '{"empleado_id":' + CAST(@IdEmpleado AS VARCHAR) + '}';
    EXEC sp_RegistrarEvento @IdUsuario, 20, @IPOrigen, @params;
END;
GO
 

IF OBJECT_ID('sp_DetalleDeducciones', 'P') IS NOT NULL DROP PROCEDURE sp_DetalleDeducciones;
GO
CREATE PROCEDURE sp_DetalleDeducciones
    @IdPlanillaSemXEmpleado INT
AS
BEGIN
    SET NOCOUNT ON;
 
    SELECT
        td.Nombre           AS NombreDeduccion,
        td.EsPorcentual,
        CASE WHEN td.EsPorcentual = 1 THEN td.Valor * 100 ELSE NULL END AS Porcentaje,
        ABS(mp.Monto)       AS MontoDeduccion
    FROM dbo.MovimientoPlanilla mp
    INNER JOIN dbo.TipoMovimiento tm ON mp.IdTipoMovimiento = tm.IdTipoMovimiento

    INNER JOIN dbo.TipoDeduccion td ON (mp.IdTipoMovimiento - 3) = td.IdTipoDeduccion
    WHERE mp.IdPlanillaSemXEmpleado = @IdPlanillaSemXEmpleado
      AND tm.Accion = '-'
    ORDER BY td.Nombre;
END;
GO
 

IF OBJECT_ID('sp_DetalleAsistenciaSemanal', 'P') IS NOT NULL DROP PROCEDURE sp_DetalleAsistenciaSemanal;
GO
CREATE PROCEDURE sp_DetalleAsistenciaSemanal
    @IdPlanillaSemXEmpleado INT
AS
BEGIN
    SET NOCOUNT ON;
 
    SELECT
        ma.FechaHoraEntrada,
        ma.FechaHoraSalida,
        tm.Nombre           AS TipoMovimiento,
        mp.Cantidad         AS Horas,
        mp.Monto
    FROM dbo.MovimientoPlanilla mp
    INNER JOIN dbo.TipoMovimiento tm ON mp.IdTipoMovimiento = tm.IdTipoMovimiento
    LEFT  JOIN dbo.MarcaAsistencia ma ON mp.IdMarcaAsistencia = ma.IdMarcaAsistencia
    WHERE mp.IdPlanillaSemXEmpleado = @IdPlanillaSemXEmpleado
      AND tm.Accion = '+'
      AND mp.IdMarcaAsistencia IS NOT NULL
    ORDER BY ma.FechaHoraEntrada;
END;
GO
 
IF OBJECT_ID('sp_ConsultarPlanillaMensual', 'P') IS NOT NULL DROP PROCEDURE sp_ConsultarPlanillaMensual;
GO
CREATE PROCEDURE sp_ConsultarPlanillaMensual
    @IdEmpleado     INT,
    @IdUsuario      INT,
    @IPOrigen       VARCHAR(45),
    @TopMeses       INT = 12
AS
BEGIN
    SET NOCOUNT ON;
 
    SELECT TOP (@TopMeses)
        mp.IdMesPlanilla,
        mp.FechaInicio,
        mp.FechaFin,
        pme.IdPlanillaMesXEmpleado,
        pme.SalarioBrutoMensual,
        pme.TotalDeduccionesMensual,
        pme.SalarioNetoMensual
    FROM dbo.PlanillaMesXEmpleado pme
    INNER JOIN dbo.MesPlanilla mp ON pme.IdMesPlanilla = mp.IdMesPlanilla
    WHERE pme.IdEmpleado = @IdEmpleado
    ORDER BY mp.FechaInicio DESC;
    DECLARE @params NVARCHAR(200) = '{"empleado_id":' + CAST(@IdEmpleado AS VARCHAR) + '}';
    EXEC sp_RegistrarEvento @IdUsuario, 21, @IPOrigen, @params;
END;
GO
  
