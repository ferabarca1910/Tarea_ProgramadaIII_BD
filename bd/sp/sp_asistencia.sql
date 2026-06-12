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
    -- 4. Insertar marca de asistencia
    DECLARE @IdMarca INT;
    INSERT INTO dbo.MarcaAsistencia (IdEmpleado, FechaHoraEntrada, FechaHoraSalida, Procesada)
    VALUES (@IdEmpleado, @FechaHoraEntrada, @FechaHoraSalida, 0);
    SET @IdMarca = SCOPE_IDENTITY();

-- 5. Calcular horas trabajadas
-- La jornada es de 8 horas. Hora fin de jornada = HoraFinJornada del dbo.TipoJornada.
-- La hora fin de jornada se aplica a la FECHA DE ENTRADA (para nocturna puede cruzar a día siguiente)
    DECLARE @FinJornadaDT DATETIME;
-- Para jornada nocturna (HoraFin < HoraInicio significa que cruza medianoche)
-- dbo.TipoJornada nocturna: inicio 22:00, fin 06:00 → fin es día siguiente
    SELECT @FinJornadaDT =
        CASE
            WHEN tj.HoraFin <= tj.HoraInicio  -- cruza medianoche
                THEN CAST(DATEADD(DAY,1,@FechaEntrada) AS DATETIME) + CAST(tj.HoraFin AS DATETIME) - CAST('00:00:00' AS DATETIME)
        ELSE
            CAST(@FechaEntrada AS DATETIME) + CAST(tj.HoraFin AS DATETIME) - CAST('00:00:00' AS DATETIME)
     END
    FROM dbo.TipoJornada tj WHERE tj.IdTipoJornada = @IdTipoJornada;

-- Horas totales trabajadas (solo enteros)
    DECLARE @MinutosTrabajados   INT = DATEDIFF(MINUTE, @FechaHoraEntrada, @FechaHoraSalida);
    DECLARE @MinutosJornada      INT = DATEDIFF(MINUTE, @FechaHoraEntrada, @FinJornadaDT);
    IF @MinutosJornada < 0 SET @MinutosJornada = 0;

-- Horas ordinarias: minutos dentro de la jornada, truncados a entero
    DECLARE @MinutosOrdinarios   INT = CASE WHEN @MinutosTrabajados <= @MinutosJornada THEN @MinutosTrabajados ELSE @MinutosJornada END;
    DECLARE @HorasOrdinarias     INT = @MinutosOrdinarios / 60;

-- Horas extras: lo que supera el fin de jornada
    DECLARE @MinutosExtra        INT = CASE WHEN @MinutosTrabajados > @MinutosJornada THEN @MinutosTrabajados - @MinutosJornada ELSE 0 END;

-- Determinar si la fecha de las horas extra es feriado/domingo
-- Las horas extra inician en @FinJornadaDT
    DECLARE @FechaExtra DATE = CAST(@FinJornadaDT AS DATE);
    DECLARE @EsFerODom  BIT  = dbo.fn_EsFeriadoODomingo(@FechaExtra);

-- Si la hora de fin de jornada es exactamente medianoche, las horas extra son en el día siguiente
-- ya se maneja porque @FechaExtra = CAST(@FinJornadaDT AS DATE)

-- Horas extras normales (no feriado, no domingo)
    DECLARE @HorasExtraNormales  INT = 0;
-- Horas extras dobles (feriado o domingo)
    DECLARE @HorasExtraDobles    INT = 0;

    IF @MinutosExtra > 0
    BEGIN
        -- Caso especial: las horas extra pueden cruzar de día normal a feriado/domingo
        -- Simplificación: tomamos la fecha en que inician las horas extra (@FechaExtra)
    IF @EsFerODom = 0
    BEGIN
        -- Verificar si cruzamos a un día feriado/domingo dentro de las horas extra
        -- Calculamos cuántos minutos quedan hasta la medianoche desde @FinJornadaDT
        DECLARE @MinHastaMedNoche INT = DATEDIFF(MINUTE, @FinJornadaDT,
            CAST(CAST(DATEADD(DAY,1,CAST(@FinJornadaDT AS DATE)) AS VARCHAR(10)) AS DATETIME));

        IF @MinutosExtra <= @MinHastaMedNoche
            -- Todo dentro del mismo día (no feriado/domingo)
            SET @HorasExtraNormales = @MinutosExtra / 60;
        ELSE
        BEGIN
            -- Parte antes de medianoche (normal) y parte después (verificar)
            DECLARE @EsSigDiaFerODom BIT = dbo.fn_EsFeriadoODomingo(DATEADD(DAY,1,@FechaExtra));
            SET @HorasExtraNormales = @MinHastaMedNoche / 60;
            DECLARE @MinExtraEnSigDia INT = @MinutosExtra - @MinHastaMedNoche;
            IF @EsSigDiaFerODom = 1
                SET @HorasExtraDobles  = @MinExtraEnSigDia / 60;
            ELSE
                SET @HorasExtraNormales = @HorasExtraNormales + (@MinExtraEnSigDia / 60);
        END;
    END
    ELSE
        -- La fecha de inicio de horas extra ya es feriado/domingo
        SET @HorasExtraDobles = @MinutosExtra / 60;
  END;
         -- 6. Generar movimientos y acumular en planilla semanal
    DECLARE @MontoOrdinario     DECIMAL(12,2) = @HorasOrdinarias    * @SalarioXHora;
    DECLARE @MontoExtraNormal   DECIMAL(12,2) = @HorasExtraNormales * @SalarioXHora * 1.5;
    DECLARE @MontoExtraDoble    DECIMAL(12,2) = @HorasExtraDobles   * @SalarioXHora * 2.0;

    -- Movimiento horas ordinarias (IdTipoMovimiento = 1)
    IF @HorasOrdinarias > 0
        INSERT INTO dbo.MovimientoPlanilla (IdPlanillaSemXEmpleado, IdTipoMovimiento, IdMarcaAsistencia, Fecha, Cantidad, Monto)
            VALUES (@IdPlanillaSemXEmpleado, 1, @IdMarca, @FechaEntrada, @HorasOrdinarias, @MontoOrdinario);

        -- Movimiento horas extra normales (IdTipoMovimiento = 2)
        IF @HorasExtraNormales > 0
            INSERT INTO dbo.MovimientoPlanilla (IdPlanillaSemXEmpleado, IdTipoMovimiento, IdMarcaAsistencia, Fecha, Cantidad, Monto)
            VALUES (@IdPlanillaSemXEmpleado, 2, @IdMarca, @FechaEntrada, @HorasExtraNormales, @MontoExtraNormal);

        -- Movimiento horas extra dobles (IdTipoMovimiento = 3)
        IF @HorasExtraDobles > 0
            INSERT INTO dbo.MovimientoPlanilla (IdPlanillaSemXEmpleado, IdTipoMovimiento, IdMarcaAsistencia, Fecha, Cantidad, Monto)
            VALUES (@IdPlanillaSemXEmpleado, 3, @IdMarca, @FechaEntrada, @HorasExtraDobles, @MontoExtraDoble);

        -- 7. Acumular en dbo.PlanillaSemXEmpleado
        UPDATE dbo.PlanillaSemXEmpleado
        SET
            SalarioBruto       = SalarioBruto       + @MontoOrdinario + @MontoExtraNormal + @MontoExtraDoble,
            HorasOrdinarias    = HorasOrdinarias    + @HorasOrdinarias,
            HorasExtraNormales = HorasExtraNormales + @HorasExtraNormales,
            HorasExtraDobles   = HorasExtraDobles   + @HorasExtraDobles
        WHERE IdPlanillaSemXEmpleado = @IdPlanillaSemXEmpleado;

        -- 8. Marcar la marca como procesada
        UPDATE dbo.MarcaAsistencia SET Procesada = 1 WHERE IdMarcaAsistencia = @IdMarca;

        -- 9. Registrar en bitácora (evento tipo 14 = Ingreso marcas asistencia)
        DECLARE @params NVARCHAR(500) = '{"empleado_doc":"' + @ValorDocumento +
            '","entrada":"' + CONVERT(VARCHAR,@FechaHoraEntrada,120) +
            '","salida":"'  + CONVERT(VARCHAR,@FechaHoraSalida,120)  + '"}';
        EXEC sp_RegistrarEvento @IdUsuarioSistema, 22, @IPOrigen, @params;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @msg VARCHAR(500) = ERROR_MESSAGE();
        RAISERROR('Error en sp_ProcesarAsistencia: %s', 16, 1, @msg);
    END CATCH;
END;
GO
