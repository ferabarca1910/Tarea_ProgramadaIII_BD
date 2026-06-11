-- ============================================================
-- SP_ASISTENCIA: Procesamiento de marcas de asistencia
-- Calcula horas ordinarias, extras normales y extras dobles.
-- ============================================================

USE PlanillaObrera;
GO

-- ============================================================
-- Función auxiliar: ¿Es feriado o domingo una fecha?
-- ============================================================
IF OBJECT_ID('dbo.fn_EsFeriadoODomingo', 'FN') IS NOT NULL DROP FUNCTION dbo.fn_EsFeriadoODomingo;
GO
CREATE FUNCTION dbo.fn_EsFeriadoODomingo(@fecha DATE)
RETURNS BIT
AS
BEGIN
    -- DATEPART: 1=domingo, 7=sábado en SQL Server (datefirst=7 default)
    IF DATEPART(WEEKDAY, @fecha) = 1  RETURN 1;  -- domingo
    IF EXISTS (SELECT 1 FROM dbo.Feriado WHERE Fecha = @fecha) RETURN 1;
    RETURN 0;
END;
GO

-- ============================================================
-- SP: Registrar bitácora (helper interno)
-- ============================================================
IF OBJECT_ID('sp_RegistrarEvento', 'P') IS NOT NULL DROP PROCEDURE sp_RegistrarEvento;
GO
CREATE PROCEDURE sp_RegistrarEvento
    @IdUsuario      INT,
    @IdTipoEvento   INT,
    @IPOrigen       VARCHAR(45),
    @Parametros     NVARCHAR(MAX) = NULL,
    @DatosAntes     NVARCHAR(MAX) = NULL,
    @DatosDespues   NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.BitacoraEvento (IdUsuario, IdTipoEvento, IPOrigen, FechaHora, Parametros, DatosAntes, DatosDespues)
    VALUES (@IdUsuario, @IdTipoEvento, @IPOrigen, GETDATE(), @Parametros, @DatosAntes, @DatosDespues);
END;
GO
-- ============================================================
-- SP: Procesar una marca de asistencia individual
-- Parámetros:
--   @ValorDocumento  : cédula del empleado (mapeo desde XML)
--   @FechaHoraEntrada / @FechaHoraSalida : DATETIME
--   @IdUsuarioSistema: usuario del proceso de simulación
--   @IPOrigen        : IP del proceso
-- ============================================================
IF OBJECT_ID('sp_ProcesarAsistencia', 'P') IS NOT NULL DROP PROCEDURE sp_ProcesarAsistencia;
GO
CREATE PROCEDURE sp_ProcesarAsistencia
    @ValorDocumento     VARCHAR(30),
    @FechaHoraEntrada   DATETIME,
    @FechaHoraSalida    DATETIME,
    @IdUsuarioSistema   INT,
    @IPOrigen           VARCHAR(45) = '127.0.0.1'
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
  -- 1. Obtener datos del empleado
      DECLARE @IdEmpleado     INT;
      DECLARE @IdPuesto       INT;
      DECLARE @SalarioXHora   DECIMAL(10,2);

      SELECT
          @IdEmpleado   = e.IdEmpleado,
          @IdPuesto     = e.IdPuesto,
          @SalarioXHora = p.SalarioXHora
      FROM dbo.Empleado e
      INNER JOIN dbo.Puesto p ON e.IdPuesto = p.IdPuesto
      WHERE e.ValorDocumento = @ValorDocumento
        AND e.Activo = 1;

      IF @IdEmpleado IS NULL
      BEGIN
          RAISERROR('dbo.Empleado con documento %s no encontrado.', 16, 1, @ValorDocumento);
          ROLLBACK; RETURN;
      END;

  -- 2. Obtener jornada de la semana actual (la semana que contiene FechaEntrada)
  DECLARE @FechaEntrada   DATE = CAST(@FechaHoraEntrada AS DATE);
  DECLARE @IdTipoJornada  INT;
  DECLARE @HoraFinJornada TIME;

  -- La semana inicia el viernes anterior o igual a la fecha
  -- FechaInicioSemana = viernes <= @FechaEntrada más reciente
  SELECT TOP 1
      @IdTipoJornada  = jes.IdTipoJornada,
      @HoraFinJornada = tj.HoraFin
  FROM dbo.JornadaEmpleadoSemana jes
  INNER JOIN dbo.TipoJornada tj ON jes.IdTipoJornada = tj.IdTipoJornada
  WHERE jes.IdEmpleado = @IdEmpleado
    AND jes.FechaInicioSemana <= @FechaEntrada
  ORDER BY jes.FechaInicioSemana DESC;

  IF @IdTipoJornada IS NULL
  BEGIN
      RAISERROR('No hay jornada asignada para el empleado %d en la fecha %s.', 16, 1, @IdEmpleado, CONVERT(VARCHAR,@FechaEntrada,103));
      ROLLBACK; RETURN;
  END;

  -- 3. Obtener la planilla semanal activa del empleado
  DECLARE @IdPlanillaSemXEmpleado INT;

  SELECT TOP 1 @IdPlanillaSemXEmpleado = pse.IdPlanillaSemXEmpleado
  FROM dbo.PlanillaSemXEmpleado pse
  INNER JOIN dbo.SemanaPlanilla sp ON pse.IdSemanaPlanilla = sp.IdSemanaPlanilla
  WHERE pse.IdEmpleado = @IdEmpleado
    AND sp.Cerrada = 0
    AND sp.FechaInicio <= @FechaEntrada
    AND sp.FechaFin    >= @FechaEntrada;

  IF @IdPlanillaSemXEmpleado IS NULL
  BEGIN
      RAISERROR('No hay planilla semanal abierta para el empleado %d.', 16, 1, @IdEmpleado);
      ROLLBACK; RETURN;
  END;
