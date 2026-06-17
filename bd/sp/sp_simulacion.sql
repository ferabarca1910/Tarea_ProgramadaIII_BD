
-- semana y mes, y SP maestro que ejecuta toda la simulacion



USE PlanillaObrera;
GO

--Determina si una fecha es domingo o feriado
--Usada para calcular si las horas extra son normales o dobles

IF OBJECT_ID('dbo.fn_EsFeriadoODomingo', 'FN') IS NOT NULL
    DROP FUNCTION dbo.fn_EsFeriadoODomingo;
GO

CREATE FUNCTION dbo.fn_EsFeriadoODomingo(@inFecha DATE)
RETURNS BIT
AS
BEGIN

    DECLARE @vEsFeriadoODomingo BIT = 0;

    IF (DATEPART(WEEKDAY, @inFecha) = 1)
        SET @vEsFeriadoODomingo = 1;

    IF EXISTS (
        SELECT 1
        FROM dbo.Feriado AS f
        WHERE (f.Fecha = @inFecha)
    )
        SET @vEsFeriadoODomingo = 1;

    RETURN @vEsFeriadoODomingo;

END;
GO

--Calcula el ultimo jueves de un mes dado
--Usada para determinar el cierre mensual de la planilla

IF OBJECT_ID('dbo.fn_UltimoJuevesDelMes', 'FN') IS NOT NULL
    DROP FUNCTION dbo.fn_UltimoJuevesDelMes;
GO

CREATE FUNCTION dbo.fn_UltimoJuevesDelMes(@inAnio INT, @inMes INT)
RETURNS DATE
AS
BEGIN

    DECLARE @vUltimoDia DATE;
    DECLARE @vDia       DATE;

    SET @vUltimoDia = EOMONTH(
        CAST(CAST(@inAnio AS VARCHAR(4)) + '-' + RIGHT('0' + CAST(@inMes AS VARCHAR(2)), 2) + '-01' AS DATE)
    );
    SET @vDia = @vUltimoDia;

    WHILE (DATEPART(WEEKDAY, @vDia) <> 5)
        SET @vDia = DATEADD(DAY, -1, @vDia);

    RETURN @vDia;

END;
GO

--Cuenta cuantos jueves hay entre dos fechas
--Determina si un mes planilla tiene 4 o 5 semanas

IF OBJECT_ID('dbo.fn_ContarJueves', 'FN') IS NOT NULL
    DROP FUNCTION dbo.fn_ContarJueves;
GO

CREATE FUNCTION dbo.fn_ContarJueves(@inFechaInicio DATE, @inFechaFin DATE)
RETURNS TINYINT
AS
BEGIN

    DECLARE @vCantidad TINYINT = 0;

    ;WITH Fechas AS (
        SELECT @inFechaInicio AS Fecha
        UNION ALL
        SELECT DATEADD(DAY, 1, Fecha)
        FROM Fechas
        WHERE (Fecha < @inFechaFin)
    )
    SELECT @vCantidad = COUNT(*)
    FROM Fechas
    WHERE (DATEPART(WEEKDAY, Fecha) = 5)
    OPTION (MAXRECURSION 60);

    RETURN @vCantidad;

END;
GO


--SP: Inicializa el sistema antes de correr la simulacion

IF OBJECT_ID('dbo.sp_InicializarSistema', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_InicializarSistema;
GO

CREATE PROCEDURE dbo.sp_InicializarSistema
    @inFechaInicioSimulacion   DATE
  , @outResultCode             INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @outResultCode = 0;

    DECLARE @vFechaFinMes  DATE;
    DECLARE @vMesInicio    INT;
    DECLARE @vAnioInicio   INT;
    DECLARE @vNumJueves    TINYINT;
    DECLARE @vIdMes        INT;
    DECLARE @vFechaFinSem  DATE;

    SET @vMesInicio  = MONTH(@inFechaInicioSimulacion);
    SET @vAnioInicio = YEAR(@inFechaInicioSimulacion);
    SET @vFechaFinMes = dbo.fn_UltimoJuevesDelMes(@vAnioInicio, @vMesInicio);
    SET @vNumJueves   = dbo.fn_ContarJueves(@inFechaInicioSimulacion, @vFechaFinMes);
    SET @vFechaFinSem = DATEADD(DAY, 6, @inFechaInicioSimulacion);

    BEGIN TRY

        INSERT INTO dbo.MesPlanilla (
            FechaInicio
          , FechaFin
          , CantidadJueves
          , Cerrado
        )
        VALUES (
            @inFechaInicioSimulacion
          , @vFechaFinMes
          , @vNumJueves
          , 0
        );

        SET @vIdMes = SCOPE_IDENTITY();

        INSERT INTO dbo.SemanaPlanilla (
            IdMesPlanilla
          , FechaInicio
          , FechaFin
          , Cerrada
        )
        VALUES (
            @vIdMes
          , @inFechaInicioSimulacion
          , @vFechaFinSem
          , 0
        );

        PRINT 'Sistema inicializado. Primera semana: '
            + CONVERT(VARCHAR, @inFechaInicioSimulacion, 103) + ' - '
            + CONVERT(VARCHAR, @vFechaFinSem, 103);

    END TRY
    BEGIN CATCH

        SET @outResultCode = 50008;

        INSERT INTO dbo.DBErrors (
            NombreSP
          , Mensaje
          , Severidad
          , Estado
          , Linea
        )
        VALUES (
            'sp_InicializarSistema'
          , ERROR_MESSAGE()
          , ERROR_SEVERITY()
          , ERROR_STATE()
          , ERROR_LINE()
        );

    END CATCH

END;
GO

--Procesa una marca de asistencia individual
--Calcula horas ordinarias, extra normales y extra dobles
--Inserta los movimientos correspondientes y actualiza
--el acumulado semanal del empleado, todo en una transaccion

IF OBJECT_ID('dbo.sp_ProcesarAsistencia', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ProcesarAsistencia;
GO

CREATE PROCEDURE dbo.sp_ProcesarAsistencia
    @inValorDocumento       VARCHAR(30)
  , @inFechaHoraEntrada     DATETIME
  , @inFechaHoraSalida      DATETIME
  , @inIdUsuarioSistema     INT
  , @inIPOrigen             VARCHAR(45) = '127.0.0.1'
  , @outResultCode          INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @outResultCode = 0;

    --declaraciones y calculos antes de abrir transaccion

    DECLARE @vIdEmpleado            INT;
    DECLARE @vSalarioXHora           DECIMAL(10,2);
    DECLARE @vFechaEntrada           DATE;
    DECLARE @vIdTipoJornada          INT;
    DECLARE @vIdPlanillaSemXEmpleado INT;
    DECLARE @vFinJornadaDT           DATETIME;
    DECLARE @vMinutosTrabajados      INT;
    DECLARE @vMinutosJornada         INT;
    DECLARE @vMinutosOrdinarios      INT;
    DECLARE @vHorasOrdinarias        INT;
    DECLARE @vMinutosExtra           INT;
    DECLARE @vFechaExtra             DATE;
    DECLARE @vEsFerODom              BIT;
    DECLARE @vHorasExtraNormales     INT = 0;
    DECLARE @vHorasExtraDobles       INT = 0;
    DECLARE @vMinHastaMedNoche       INT;
    DECLARE @vEsSigDiaFerODom        BIT;
    DECLARE @vMinExtraEnSigDia       INT;
    DECLARE @vMontoOrdinario         DECIMAL(12,2);
    DECLARE @vMontoExtraNormal       DECIMAL(12,2);
    DECLARE @vMontoExtraDoble        DECIMAL(12,2);
    DECLARE @vIdMarca                INT;
    DECLARE @vParams                 NVARCHAR(500);

    SET @vFechaEntrada = CAST(@inFechaHoraEntrada AS DATE);

    SELECT
        @vIdEmpleado   = e.IdEmpleado
      , @vSalarioXHora = p.SalarioXHora
    FROM dbo.Empleado AS e
    INNER JOIN dbo.Puesto AS p
        ON (p.IdPuesto = e.IdPuesto)
    WHERE (e.ValorDocumentoIdentidad = @inValorDocumento)
      AND (e.Activo = 1);

    IF (@vIdEmpleado IS NULL)
    BEGIN
        SET @outResultCode = 50012;
        RETURN;
    END;

    SELECT TOP (1)
        @vIdTipoJornada = jes.IdTipoJornada
    FROM dbo.JornadaEmpleadoSemana AS jes
    WHERE (jes.IdEmpleado = @vIdEmpleado)
      AND (jes.FechaInicioSemana <= @vFechaEntrada)
    ORDER BY jes.FechaInicioSemana DESC;

    IF (@vIdTipoJornada IS NULL)
    BEGIN
        SET @outResultCode = 50013;
        RETURN;
    END;

    SELECT
        @vFinJornadaDT =
            CASE
                WHEN (tj.HoraFin <= tj.HoraInicio)
                    THEN CAST(DATEADD(DAY, 1, @vFechaEntrada) AS DATETIME)
                         + CAST(tj.HoraFin AS DATETIME) - CAST('00:00:00' AS DATETIME)
                ELSE
                    CAST(@vFechaEntrada AS DATETIME)
                    + CAST(tj.HoraFin AS DATETIME) - CAST('00:00:00' AS DATETIME)
            END
    FROM dbo.TipoJornada AS tj
    WHERE (tj.IdTipoJornada = @vIdTipoJornada);

    SELECT TOP (1)
        @vIdPlanillaSemXEmpleado = pse.IdPlanillaSemXEmpleado
    FROM dbo.PlanillaSemXEmpleado AS pse
    INNER JOIN dbo.SemanaPlanilla AS sp
        ON (sp.IdSemanaPlanilla = pse.IdSemanaPlanilla)
    WHERE (pse.IdEmpleado = @vIdEmpleado)
      AND (sp.Cerrada = 0)
      AND (sp.FechaInicio <= @vFechaEntrada)
      AND (sp.FechaFin >= @vFechaEntrada);

    IF (@vIdPlanillaSemXEmpleado IS NULL)
    BEGIN
        SET @outResultCode = 50014;
        RETURN;
    END;

    --Calculo de minutos trabajados vs minutos de jornada
    SET @vMinutosTrabajados = DATEDIFF(MINUTE, @inFechaHoraEntrada, @inFechaHoraSalida);
    SET @vMinutosJornada    = DATEDIFF(MINUTE, @inFechaHoraEntrada, @vFinJornadaDT);

    IF (@vMinutosJornada < 0)
        SET @vMinutosJornada = 0;

    SET @vMinutosOrdinarios = CASE
        WHEN (@vMinutosTrabajados <= @vMinutosJornada) THEN @vMinutosTrabajados
        ELSE @vMinutosJornada
    END;
    SET @vHorasOrdinarias = @vMinutosOrdinarios / 60;

    SET @vMinutosExtra = CASE
        WHEN (@vMinutosTrabajados > @vMinutosJornada) THEN (@vMinutosTrabajados - @vMinutosJornada)
        ELSE 0
    END;

    SET @vFechaExtra = CAST(@vFinJornadaDT AS DATE);
    SET @vEsFerODom  = dbo.fn_EsFeriadoODomingo(@vFechaExtra);

    IF (@vMinutosExtra > 0)
    BEGIN

        IF (@vEsFerODom = 0)
        BEGIN

            SET @vMinHastaMedNoche = DATEDIFF(
                MINUTE
              , @vFinJornadaDT
              , CAST(DATEADD(DAY, 1, CAST(@vFinJornadaDT AS DATE)) AS DATETIME)
            );

            IF (@vMinutosExtra <= @vMinHastaMedNoche)
            BEGIN
                SET @vHorasExtraNormales = @vMinutosExtra / 60;
            END
            ELSE
            BEGIN
                SET @vEsSigDiaFerODom  = dbo.fn_EsFeriadoODomingo(DATEADD(DAY, 1, @vFechaExtra));
                SET @vHorasExtraNormales = @vMinHastaMedNoche / 60;
                SET @vMinExtraEnSigDia  = @vMinutosExtra - @vMinHastaMedNoche;

                IF (@vEsSigDiaFerODom = 1)
                    SET @vHorasExtraDobles = @vMinExtraEnSigDia / 60;
                ELSE
                    SET @vHorasExtraNormales = @vHorasExtraNormales + (@vMinExtraEnSigDia / 60);
            END;

        END
        ELSE
        BEGIN
            SET @vHorasExtraDobles = @vMinutosExtra / 60;
        END;

    END;

    SET @vMontoOrdinario   = @vHorasOrdinarias    * @vSalarioXHora;
    SET @vMontoExtraNormal = @vHorasExtraNormales * @vSalarioXHora * 1.5;
    SET @vMontoExtraDoble  = @vHorasExtraDobles   * @vSalarioXHora * 2.0;

    --Transaccion al final: solo INSERTs/UPDATEs

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO dbo.MarcaAsistencia (
            IdEmpleado
          , FechaHoraEntrada
          , FechaHoraSalida
          , FechaOperacion
        )
        VALUES (
            @vIdEmpleado
          , @inFechaHoraEntrada
          , @inFechaHoraSalida
          , @vFechaEntrada
        );

        SET @vIdMarca = SCOPE_IDENTITY();

        IF (@vHorasOrdinarias > 0)
            INSERT INTO dbo.MovimientoPlanilla (
                IdPlanillaSemXEmpleado
              , IdTipoMovimiento
              , IdMarcaAsistencia
              , Fecha
              , Cantidad
              , Monto
            )
            VALUES (
                @vIdPlanillaSemXEmpleado
              , 1
              , @vIdMarca
              , @vFechaEntrada
              , @vHorasOrdinarias
              , @vMontoOrdinario
            );

        IF (@vHorasExtraNormales > 0)
            INSERT INTO dbo.MovimientoPlanilla (
                IdPlanillaSemXEmpleado
              , IdTipoMovimiento
              , IdMarcaAsistencia
              , Fecha
              , Cantidad
              , Monto
            )
            VALUES (
                @vIdPlanillaSemXEmpleado
              , 2
              , @vIdMarca
              , @vFechaEntrada
              , @vHorasExtraNormales
              , @vMontoExtraNormal
            );

        IF (@vHorasExtraDobles > 0)
            INSERT INTO dbo.MovimientoPlanilla (
                IdPlanillaSemXEmpleado
              , IdTipoMovimiento
              , IdMarcaAsistencia
              , Fecha
              , Cantidad
              , Monto
            )
            VALUES (
                @vIdPlanillaSemXEmpleado
              , 3
              , @vIdMarca
              , @vFechaEntrada
              , @vHorasExtraDobles
              , @vMontoExtraDoble
            );

        UPDATE dbo.PlanillaSemXEmpleado
        SET
            SalarioBruto       = SalarioBruto       + @vMontoOrdinario + @vMontoExtraNormal + @vMontoExtraDoble
          , HorasOrdinarias    = HorasOrdinarias    + @vHorasOrdinarias
          , HorasExtraNormales = HorasExtraNormales + @vHorasExtraNormales
          , HorasExtraDobles   = HorasExtraDobles   + @vHorasExtraDobles
        WHERE (IdPlanillaSemXEmpleado = @vIdPlanillaSemXEmpleado);

        SET @vParams =
            N'{"empleado_doc":"' + @inValorDocumento
            + N'","entrada":"' + CONVERT(VARCHAR, @inFechaHoraEntrada, 120)
            + N'","salida":"'  + CONVERT(VARCHAR, @inFechaHoraSalida, 120) + N'"}';

        INSERT INTO dbo.BitacoraEvento (
            IdUsuario
          , IdTipoEvento
          , IPOrigen
          , Parametros
        )
        VALUES (
            @inIdUsuarioSistema
          , 14
          , @inIPOrigen
          , @vParams
        );

        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH

        IF (@@TRANCOUNT > 0)
            ROLLBACK TRANSACTION;

        SET @outResultCode = 50008;

        INSERT INTO dbo.DBErrors (
            NombreSP
          , Mensaje
          , Severidad
          , Estado
          , Linea
        )
        VALUES (
            'sp_ProcesarAsistencia'
          , ERROR_MESSAGE()
          , ERROR_SEVERITY()
          , ERROR_STATE()
          , ERROR_LINE()
        );

    END CATCH

END;
GO


--SP: Cierre semanal de planilla (se ejecuta los jueves)

IF OBJECT_ID('dbo.sp_CierreSemanal', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_CierreSemanal;
GO

CREATE PROCEDURE dbo.sp_CierreSemanal
    @inFechaJueves      DATE
  , @inIdUsuarioSistema INT
  , @inIPOrigen         VARCHAR(45) = '127.0.0.1'
  , @outResultCode      INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @outResultCode = 0;

    --Pre-proceso: identificar la semana y el mes

    DECLARE @vIdSemanaPlanilla INT;
    DECLARE @vIdMesPlanilla    INT;
    DECLARE @vCantidadJueves   TINYINT;

    SELECT
        @vIdSemanaPlanilla = sp.IdSemanaPlanilla
      , @vIdMesPlanilla    = sp.IdMesPlanilla
    FROM dbo.SemanaPlanilla AS sp
    WHERE (sp.FechaFin = @inFechaJueves)
      AND (sp.Cerrada = 0);

    IF (@vIdSemanaPlanilla IS NULL)
    BEGIN
        SET @outResultCode = 50015;
        RETURN;
    END;

    SELECT
        @vCantidadJueves = mp.CantidadJueves
    FROM dbo.MesPlanilla AS mp
    WHERE (mp.IdMesPlanilla = @vIdMesPlanilla);

    --Tabla variable con las deducciones porcentuales a aplicar por empleado
    DECLARE @tDeduccionesPct TABLE (
        IdPlanillaSemXEmpleado   INT
      , IdPlanillaMesXEmpleado   INT
      , IdTipoDeduccion          INT
      , Monto                    DECIMAL(12,2)
    );

    INSERT INTO @tDeduccionesPct (
        IdPlanillaSemXEmpleado
      , IdPlanillaMesXEmpleado
      , IdTipoDeduccion
      , Monto
    )
    SELECT
        pse.IdPlanillaSemXEmpleado
      , pme.IdPlanillaMesXEmpleado
      , de.IdTipoDeduccion
      , ROUND(pse.SalarioBruto * td.Valor, 2)
    FROM dbo.PlanillaSemXEmpleado AS pse
    INNER JOIN dbo.DeduccionEmpleado AS de
        ON (de.IdEmpleado = pse.IdEmpleado)
    INNER JOIN dbo.TipoDeduccion AS td
        ON (td.IdTipoDeduccion = de.IdTipoDeduccion)
    LEFT JOIN dbo.PlanillaMesXEmpleado AS pme
        ON (pme.IdEmpleado = pse.IdEmpleado)
       AND (pme.IdMesPlanilla = @vIdMesPlanilla)
    WHERE (pse.IdSemanaPlanilla = @vIdSemanaPlanilla)
      AND (td.EsPorcentual = 1)
      AND (de.FechaInicio <= @inFechaJueves)
      AND (de.FechaFin IS NULL OR de.FechaFin >= @inFechaJueves);

    -- Tabla variable con las deducciones de monto fijo a aplicar por empleado
    DECLARE @tDeduccionesFijas TABLE (
        IdPlanillaSemXEmpleado   INT
      , IdPlanillaMesXEmpleado   INT
      , IdTipoDeduccion          INT
      , Monto                    DECIMAL(12,2)
    );

    INSERT INTO @tDeduccionesFijas (
        IdPlanillaSemXEmpleado
      , IdPlanillaMesXEmpleado
      , IdTipoDeduccion
      , Monto
    )
    SELECT
        pse.IdPlanillaSemXEmpleado
      , pme.IdPlanillaMesXEmpleado
      , de.IdTipoDeduccion
      , ROUND(de.Valor / @vCantidadJueves, 2)
    FROM dbo.PlanillaSemXEmpleado AS pse
    INNER JOIN dbo.DeduccionEmpleado AS de
        ON (de.IdEmpleado = pse.IdEmpleado)
    INNER JOIN dbo.TipoDeduccion AS td
        ON (td.IdTipoDeduccion = de.IdTipoDeduccion)
    LEFT JOIN dbo.PlanillaMesXEmpleado AS pme
        ON (pme.IdEmpleado = pse.IdEmpleado)
       AND (pme.IdMesPlanilla = @vIdMesPlanilla)
    WHERE (pse.IdSemanaPlanilla = @vIdSemanaPlanilla)
      AND (td.EsPorcentual = 0)
      AND (de.Valor > 0)
      AND (de.FechaInicio <= @inFechaJueves)
      AND (de.FechaFin IS NULL OR de.FechaFin >= @inFechaJueves);

    --Transaccion: insertar movimientos y actualizar acumulados

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Insertar movimientos de debito por deducciones porcentuales
        INSERT INTO dbo.MovimientoPlanilla (
            IdPlanillaSemXEmpleado
          , IdTipoMovimiento
          , Fecha
          , Cantidad
          , Monto
        )
        SELECT
            dp.IdPlanillaSemXEmpleado
          , td.IdTipoMovimiento
          , @inFechaJueves
          , 0
          , -dp.Monto
        FROM @tDeduccionesPct AS dp
        INNER JOIN dbo.TipoDeduccion AS td
            ON (td.IdTipoDeduccion = dp.IdTipoDeduccion);

        --Insertar movimientos de debito por deducciones fijas
        INSERT INTO dbo.MovimientoPlanilla (
            IdPlanillaSemXEmpleado
          , IdTipoMovimiento
          , Fecha
          , Cantidad
          , Monto
        )
        SELECT
            df.IdPlanillaSemXEmpleado
          , td.IdTipoMovimiento
          , @inFechaJueves
          , 0
          , -df.Monto
        FROM @tDeduccionesFijas AS df
        INNER JOIN dbo.TipoDeduccion AS td
            ON (td.IdTipoDeduccion = df.IdTipoDeduccion);

        --Actualizar TotalDeducciones y SalarioNeto de la semana
        UPDATE pse
        SET
            pse.TotalDeducciones = ISNULL(t.MontoTotal, 0)
          , pse.SalarioNeto      = pse.SalarioBruto - ISNULL(t.MontoTotal, 0)
        FROM dbo.PlanillaSemXEmpleado AS pse
        LEFT JOIN (
            SELECT
                IdPlanillaSemXEmpleado
              , SUM(Monto) AS MontoTotal
            FROM (
                SELECT IdPlanillaSemXEmpleado, Monto FROM @tDeduccionesPct
                UNION ALL
                SELECT IdPlanillaSemXEmpleado, Monto FROM @tDeduccionesFijas
            ) AS u
            GROUP BY IdPlanillaSemXEmpleado
        ) AS t
            ON (t.IdPlanillaSemXEmpleado = pse.IdPlanillaSemXEmpleado)
        WHERE (pse.IdSemanaPlanilla = @vIdSemanaPlanilla);

        --Acumular deducciones porcentuales en el resumen mensual
        MERGE dbo.DeduccionXEmpleadoXMes AS dest
        USING (
            SELECT
                IdPlanillaMesXEmpleado
              , IdTipoDeduccion
              , SUM(Monto) AS Monto
            FROM @tDeduccionesPct
            WHERE (IdPlanillaMesXEmpleado IS NOT NULL)
            GROUP BY IdPlanillaMesXEmpleado, IdTipoDeduccion
        ) AS src
            ON (dest.IdPlanillaMesXEmpleado = src.IdPlanillaMesXEmpleado)
           AND (dest.IdTipoDeduccion = src.IdTipoDeduccion)
        WHEN MATCHED THEN
            UPDATE SET MontoTotal = dest.MontoTotal + src.Monto
        WHEN NOT MATCHED THEN
            INSERT (IdPlanillaMesXEmpleado, IdTipoDeduccion, MontoTotal)
            VALUES (src.IdPlanillaMesXEmpleado, src.IdTipoDeduccion, src.Monto);

        --Acumular deducciones fijas en el resumen mensual
        MERGE dbo.DeduccionXEmpleadoXMes AS dest
        USING (
            SELECT
                IdPlanillaMesXEmpleado
              , IdTipoDeduccion
              , SUM(Monto) AS Monto
            FROM @tDeduccionesFijas
            WHERE (IdPlanillaMesXEmpleado IS NOT NULL)
            GROUP BY IdPlanillaMesXEmpleado, IdTipoDeduccion
        ) AS src
            ON (dest.IdPlanillaMesXEmpleado = src.IdPlanillaMesXEmpleado)
           AND (dest.IdTipoDeduccion = src.IdTipoDeduccion)
        WHEN MATCHED THEN
            UPDATE SET MontoTotal = dest.MontoTotal + src.Monto
        WHEN NOT MATCHED THEN
            INSERT (IdPlanillaMesXEmpleado, IdTipoDeduccion, MontoTotal)
            VALUES (src.IdPlanillaMesXEmpleado, src.IdTipoDeduccion, src.Monto);

        --Acumular SalarioBruto y deducciones de la semana en el mes
        UPDATE pme
        SET
            pme.SalarioBrutoMensual     = pme.SalarioBrutoMensual     + pse.SalarioBruto
          , pme.TotalDeduccionesMensual = pme.TotalDeduccionesMensual + pse.TotalDeducciones
          , pme.SalarioNetoMensual      = pme.SalarioNetoMensual      + pse.SalarioNeto
        FROM dbo.PlanillaMesXEmpleado AS pme
        INNER JOIN dbo.PlanillaSemXEmpleado AS pse
            ON (pse.IdEmpleado = pme.IdEmpleado)
        WHERE (pse.IdSemanaPlanilla = @vIdSemanaPlanilla)
          AND (pme.IdMesPlanilla = @vIdMesPlanilla);

        --Cerrar la semana
        UPDATE dbo.SemanaPlanilla
        SET Cerrada = 1
        WHERE (IdSemanaPlanilla = @vIdSemanaPlanilla);

        INSERT INTO dbo.BitacoraEvento (
            IdUsuario
          , IdTipoEvento
          , IPOrigen
          , Parametros
        )
        VALUES (
            @inIdUsuarioSistema
          , 14
          , @inIPOrigen
          , N'{"cierre_semanal":"' + CONVERT(VARCHAR, @inFechaJueves, 120) + N'"}'
        );

        COMMIT TRANSACTION;

        PRINT 'Cierre semanal del ' + CONVERT(VARCHAR, @inFechaJueves, 103) + ' completado.';

    END TRY
    BEGIN CATCH

        IF (@@TRANCOUNT > 0)
            ROLLBACK TRANSACTION;

        SET @outResultCode = 50008;

        INSERT INTO dbo.DBErrors (
            NombreSP
          , Mensaje
          , Severidad
          , Estado
          , Linea
        )
        VALUES (
            'sp_CierreSemanal'
          , ERROR_MESSAGE()
          , ERROR_SEVERITY()
          , ERROR_STATE()
          , ERROR_LINE()
        );

    END CATCH

END;
GO


--SP: Apertura de una nueva semana de planilla
--Crea el encabezado de semana y un registro PlanillaSemXEmpleado
--en cero para cada empleado activo

IF OBJECT_ID('dbo.sp_AperturaSemana', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_AperturaSemana;
GO

CREATE PROCEDURE dbo.sp_AperturaSemana
    @inFechaInicioSemana    DATE
  , @inFechaFinSemana       DATE
  , @outResultCode          INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @outResultCode = 0;

    DECLARE @vIdMesPlanilla    INT;
    DECLARE @vIdSemanaPlanilla INT;

    SELECT
        @vIdMesPlanilla = mp.IdMesPlanilla
    FROM dbo.MesPlanilla AS mp
    WHERE (mp.FechaInicio <= @inFechaInicioSemana)
      AND (mp.FechaFin >= @inFechaFinSemana)
      AND (mp.Cerrado = 0);

    IF (@vIdMesPlanilla IS NULL)
    BEGIN
        SET @outResultCode = 50016;
        RETURN;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO dbo.SemanaPlanilla (
            IdMesPlanilla
          , FechaInicio
          , FechaFin
          , Cerrada
        )
        VALUES (
            @vIdMesPlanilla
          , @inFechaInicioSemana
          , @inFechaFinSemana
          , 0
        );

        SET @vIdSemanaPlanilla = SCOPE_IDENTITY();

        INSERT INTO dbo.PlanillaSemXEmpleado (
            IdSemanaPlanilla
          , IdEmpleado
          , SalarioBruto
          , TotalDeducciones
          , SalarioNeto
          , HorasOrdinarias
          , HorasExtraNormales
          , HorasExtraDobles
        )
        SELECT
            @vIdSemanaPlanilla
          , e.IdEmpleado
          , 0
          , 0
          , 0
          , 0
          , 0
          , 0
        FROM dbo.Empleado AS e
        WHERE (e.Activo = 1);

        COMMIT TRANSACTION;

        PRINT 'Apertura de semana completada. IdSemanaPlanilla=' + CAST(@vIdSemanaPlanilla AS VARCHAR(10));

    END TRY
    BEGIN CATCH

        IF (@@TRANCOUNT > 0)
            ROLLBACK TRANSACTION;

        SET @outResultCode = 50008;

        INSERT INTO dbo.DBErrors (
            NombreSP
          , Mensaje
          , Severidad
          , Estado
          , Linea
        )
        VALUES (
            'sp_AperturaSemana'
          , ERROR_MESSAGE()
          , ERROR_SEVERITY()
          , ERROR_STATE()
          , ERROR_LINE()
        );

    END CATCH

END;
GO

--SP: Apertura de un nuevo mes de planilla
--Se ejecuta cuando el jueves actual cierra y el siguiente
--dia es el primer viernes del mes

IF OBJECT_ID('dbo.sp_AperturaMes', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_AperturaMes;
GO

CREATE PROCEDURE dbo.sp_AperturaMes
    @inFechaInicioMes   DATE
  , @inFechaFinMes      DATE
  , @inCantidadJueves   TINYINT
  , @outResultCode      INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @outResultCode = 0;

    DECLARE @vIdMesPlanilla INT;

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO dbo.MesPlanilla (
            FechaInicio
          , FechaFin
          , CantidadJueves
          , Cerrado
        )
        VALUES (
            @inFechaInicioMes
          , @inFechaFinMes
          , @inCantidadJueves
          , 0
        );

        SET @vIdMesPlanilla = SCOPE_IDENTITY();

        INSERT INTO dbo.PlanillaMesXEmpleado (
            IdMesPlanilla
          , IdEmpleado
          , SalarioBrutoMensual
          , TotalDeduccionesMensual
          , SalarioNetoMensual
        )
        SELECT
            @vIdMesPlanilla
          , e.IdEmpleado
          , 0
          , 0
          , 0
        FROM dbo.Empleado AS e
        WHERE (e.Activo = 1);

        COMMIT TRANSACTION;

        PRINT 'Apertura de mes completada. IdMesPlanilla=' + CAST(@vIdMesPlanilla AS VARCHAR(10));

    END TRY
    BEGIN CATCH

        IF (@@TRANCOUNT > 0)
            ROLLBACK TRANSACTION;

        SET @outResultCode = 50008;

        INSERT INTO dbo.DBErrors (
            NombreSP
          , Mensaje
          , Severidad
          , Estado
          , Linea
        )
        VALUES (
            'sp_AperturaMes'
          , ERROR_MESSAGE()
          , ERROR_SEVERITY()
          , ERROR_STATE()
          , ERROR_LINE()
        );

    END CATCH

END;
GO


--SP MAESTRO: Ejecuta la simulacion completa
--Itera sobre cada FechaOperacion del XML, en orden ascendente,
--y para cada fecha: inserta/elimina empleados, asocia/desasocia
--deducciones, procesa asistencias, y si es jueves hace el
--cierre semanal, apertura de mes (si aplica) y apertura de
--la siguiente semana, sin usar cursores

IF OBJECT_ID('dbo.sp_EjecutarSimulacion', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_EjecutarSimulacion;
GO

CREATE PROCEDURE dbo.sp_EjecutarSimulacion
    @inXMLOperacion     XML
  , @inIdUsuarioSistema INT = 1
  , @inIPOrigen         VARCHAR(45) = '127.0.0.1'
  , @outResultCode      INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @outResultCode = 0;

    DECLARE @vResultCode INT = 0;

    --Tabla variable con todas las fechas de operacion en orden
    DECLARE @tFechas TABLE (
        Fila    INT IDENTITY(1, 1)
      , Fecha   DATE
      , NodoXML XML
    );

    INSERT INTO @tFechas (
        Fecha
      , NodoXML
    )
    SELECT
        CAST(nodo.value('@Fecha', 'VARCHAR(10)') AS DATE)
      , nodo.query('.')
    FROM @inXMLOperacion.nodes('/Operaciones/FechaOperacion') AS x(nodo)
    ORDER BY CAST(nodo.value('@Fecha', 'VARCHAR(10)') AS DATE);

    DECLARE @vTotalFilas    INT;
    DECLARE @vFilaActual    INT = 1;
    DECLARE @vFechaActual   DATE;
    DECLARE @vNodoActual    XML;
    DECLARE @vDiaSemana     INT;
    DECLARE @vEsJueves      BIT;
    DECLARE @vFechaViernes  DATE;
    DECLARE @vEsUltimoJue   BIT;
    DECLARE @vFechaFinMesSig DATE;
    DECLARE @vNumJuevesSig   TINYINT;

    SELECT @vTotalFilas = COUNT(*) FROM @tFechas;

    WHILE (@vFilaActual <= @vTotalFilas)
    BEGIN

        SELECT
            @vFechaActual = Fecha
          , @vNodoActual  = NodoXML
        FROM @tFechas
        WHERE (Fila = @vFilaActual);

        PRINT '--- Procesando fecha: ' + CONVERT(VARCHAR, @vFechaActual, 103) + ' ---';

        SET @vDiaSemana = DATEPART(WEEKDAY, @vFechaActual);
        SET @vEsJueves  = CASE WHEN (@vDiaSemana = 5) THEN 1 ELSE 0 END;

        --Insertar nuevos empleados (mapeo de Puesto por nombre)

        DECLARE @tNuevosEmpleados TABLE (
            Fila              INT IDENTITY(1, 1)
          , ValorDocumento    VARCHAR(30)
          , Nombre            VARCHAR(150)
          , NombrePuesto      VARCHAR(100)
          , CuentaBancaria    VARCHAR(30)
          , Username          VARCHAR(50)
          , Password          VARCHAR(255)
        );

        INSERT INTO @tNuevosEmpleados (
            ValorDocumento
          , Nombre
          , NombrePuesto
          , CuentaBancaria
          , Username
          , Password
        )
        SELECT
            n.value('@ValorDocumentoIdentidad', 'VARCHAR(30)')
          , n.value('@Nombre',                  'VARCHAR(150)')
          , n.value('@Puesto',                  'VARCHAR(100)')
          , n.value('@CuentaBancaria',           'VARCHAR(30)')
          , n.value('@Username',                 'VARCHAR(50)')
          , n.value('@Password',                  'VARCHAR(255)')
        FROM @vNodoActual.nodes('/FechaOperacion/InsertarEmpleado') AS x(n);

        DECLARE @vNuevoFila         INT = 1;
        DECLARE @vNuevoTotal        INT;
        DECLARE @vNuevoValorDoc     VARCHAR(30);
        DECLARE @vNuevoNombre       VARCHAR(150);
        DECLARE @vNuevoPuesto       VARCHAR(100);
        DECLARE @vNuevoCuenta       VARCHAR(30);
        DECLARE @vNuevoUsername     VARCHAR(50);
        DECLARE @vNuevoPassword     VARCHAR(255);
        DECLARE @vIdEmpleadoNuevo   INT;

        SELECT @vNuevoTotal = COUNT(*) FROM @tNuevosEmpleados;

        WHILE (@vNuevoFila <= @vNuevoTotal)
        BEGIN

            SELECT
                @vNuevoValorDoc = ValorDocumento
              , @vNuevoNombre   = Nombre
              , @vNuevoPuesto   = NombrePuesto
              , @vNuevoCuenta   = CuentaBancaria
              , @vNuevoUsername = Username
              , @vNuevoPassword = Password
            FROM @tNuevosEmpleados
            WHERE (Fila = @vNuevoFila);

            EXEC dbo.sp_InsertarEmpleado
                @Nombre          = @vNuevoNombre
              , @ValorDocumento  = @vNuevoValorDoc
              , @NombrePuesto    = @vNuevoPuesto
              , @Username        = @vNuevoUsername
              , @Password        = @vNuevoPassword
              , @CuentaBancaria  = @vNuevoCuenta
              , @FechaIngreso    = @vFechaActual
              , @IdUsuarioAdmin  = @inIdUsuarioSistema
              , @IPOrigen        = @inIPOrigen
              , @IdEmpleadoNuevo = @vIdEmpleadoNuevo OUTPUT;

            SET @vNuevoFila = @vNuevoFila + 1;

        END;

        --Eliminar empleados

        DECLARE @tEliminarEmpleados TABLE (
            Fila            INT IDENTITY(1, 1)
          , ValorDocumento  VARCHAR(30)
        );

        INSERT INTO @tEliminarEmpleados (ValorDocumento)
        SELECT
            n.value('@ValorDocumentoIdentidad', 'VARCHAR(30)')
        FROM @vNodoActual.nodes('/FechaOperacion/EliminarEmpleado') AS x(n);

        DECLARE @vElimFila  INT = 1;
        DECLARE @vElimTotal INT;
        DECLARE @vElimDoc   VARCHAR(30);

        SELECT @vElimTotal = COUNT(*) FROM @tEliminarEmpleados;

        WHILE (@vElimFila <= @vElimTotal)
        BEGIN

            SELECT @vElimDoc = ValorDocumento
            FROM @tEliminarEmpleados
            WHERE (Fila = @vElimFila);

            EXEC dbo.sp_EliminarEmpleado
                @ValorDocumento = @vElimDoc
              , @IdUsuarioAdmin = @inIdUsuarioSistema
              , @IPOrigen       = @inIPOrigen;

            SET @vElimFila = @vElimFila + 1;

        END;

        --Asociar empleados con deduccion (mapeo de TipoDeduccion por nombre via TipoMovimiento)

        DECLARE @tAsociarDeducciones TABLE (
            Fila            INT IDENTITY(1, 1)
          , ValorDocumento  VARCHAR(30)
          , NombreDeduccion VARCHAR(100)
          , MontoFijo       DECIMAL(12,2)
        );

        INSERT INTO @tAsociarDeducciones (
            ValorDocumento
          , NombreDeduccion
          , MontoFijo
        )
        SELECT
            n.value('@ValorDocumentoIdentidad', 'VARCHAR(30)')
          , n.value('@TipoDeduccion',            'VARCHAR(100)')
          , n.value('@MontoFijo',                'DECIMAL(12,2)')
        FROM @vNodoActual.nodes('/FechaOperacion/AsociaEmpleadoConDeduccion') AS x(n);

        DECLARE @vAsocFila      INT = 1;
        DECLARE @vAsocTotal     INT;
        DECLARE @vAsocDoc       VARCHAR(30);
        DECLARE @vAsocNombreDed VARCHAR(100);
        DECLARE @vAsocMonto     DECIMAL(12,2);
        DECLARE @vAsocIdTipoDed INT;
        DECLARE @vFechaInicioAsoc DATE;

        SELECT @vAsocTotal = COUNT(*) FROM @tAsociarDeducciones;
        SET @vFechaInicioAsoc = DATEADD(DAY, 1, @vFechaActual);

        WHILE (@vAsocFila <= @vAsocTotal)
        BEGIN

            SELECT
                @vAsocDoc       = ValorDocumento
              , @vAsocNombreDed = NombreDeduccion
              , @vAsocMonto     = MontoFijo
            FROM @tAsociarDeducciones
            WHERE (Fila = @vAsocFila);

            SELECT @vAsocIdTipoDed = td.IdTipoDeduccion
            FROM dbo.TipoDeduccion AS td
            INNER JOIN dbo.TipoMovimiento AS tm
                ON (tm.IdTipoMovimiento = td.IdTipoMovimiento)
            WHERE (tm.Nombre = @vAsocNombreDed);

            IF (@vAsocIdTipoDed IS NOT NULL)
                EXEC dbo.sp_AsociarDeduccion
                    @ValorDocumento  = @vAsocDoc
                  , @IdTipoDeduccion = @vAsocIdTipoDed
                  , @MontoFijo       = @vAsocMonto
                  , @FechaInicio     = @vFechaInicioAsoc
                  , @IdUsuarioAdmin  = @inIdUsuarioSistema
                  , @IPOrigen        = @inIPOrigen;

            SET @vAsocFila = @vAsocFila + 1;

        END;

        --Desasociar empleados de deduccion

        DECLARE @tDesasociarDeducciones TABLE (
            Fila            INT IDENTITY(1, 1)
          , ValorDocumento  VARCHAR(30)
          , NombreDeduccion VARCHAR(100)
        );

        INSERT INTO @tDesasociarDeducciones (
            ValorDocumento
          , NombreDeduccion
        )
        SELECT
            n.value('@ValorDocumentoIdentidad', 'VARCHAR(30)')
          , n.value('@TipoDeduccion',            'VARCHAR(100)')
        FROM @vNodoActual.nodes('/FechaOperacion/DesasociaEmpleadoConDeduccion') AS x(n);

        DECLARE @vDesFila      INT = 1;
        DECLARE @vDesTotal     INT;
        DECLARE @vDesDoc       VARCHAR(30);
        DECLARE @vDesNombreDed VARCHAR(100);
        DECLARE @vDesIdTipoDed INT;

        SELECT @vDesTotal = COUNT(*) FROM @tDesasociarDeducciones;

        WHILE (@vDesFila <= @vDesTotal)
        BEGIN

            SELECT
                @vDesDoc       = ValorDocumento
              , @vDesNombreDed = NombreDeduccion
            FROM @tDesasociarDeducciones
            WHERE (Fila = @vDesFila);

            SELECT @vDesIdTipoDed = td.IdTipoDeduccion
            FROM dbo.TipoDeduccion AS td
            INNER JOIN dbo.TipoMovimiento AS tm
                ON (tm.IdTipoMovimiento = td.IdTipoMovimiento)
            WHERE (tm.Nombre = @vDesNombreDed);

            IF (@vDesIdTipoDed IS NOT NULL)
                EXEC dbo.sp_DesasociarDeduccion
                    @ValorDocumento  = @vDesDoc
                  , @IdTipoDeduccion = @vDesIdTipoDed
                  , @FechaFin        = @vFechaActual
                  , @IdUsuarioAdmin  = @inIdUsuarioSistema
                  , @IPOrigen        = @inIPOrigen;

            SET @vDesFila = @vDesFila + 1;

        END;

        --Procesar marcas de asistencia 

        DECLARE @tMarcas TABLE (
            Fila            INT IDENTITY(1, 1)
          , ValorDocumento  VARCHAR(30)
          , HoraEntrada     DATETIME
          , HoraSalida      DATETIME
        );

        INSERT INTO @tMarcas (
            ValorDocumento
          , HoraEntrada
          , HoraSalida
        )
        SELECT
            n.value('@ValorDocumentoIdentidad', 'VARCHAR(30)')
          , CAST(n.value('@HoraEntrada', 'VARCHAR(20)') AS DATETIME)
          , CAST(n.value('@HoraSalida',  'VARCHAR(20)') AS DATETIME)
        FROM @vNodoActual.nodes('/FechaOperacion/MarcaAsistencia') AS x(n);

        DECLARE @vMarcaFila    INT = 1;
        DECLARE @vMarcaTotal   INT;
        DECLARE @vMarcaDoc     VARCHAR(30);
        DECLARE @vMarcaEntrada DATETIME;
        DECLARE @vMarcaSalida  DATETIME;

        SELECT @vMarcaTotal = COUNT(*) FROM @tMarcas;

        WHILE (@vMarcaFila <= @vMarcaTotal)
        BEGIN

            SELECT
                @vMarcaDoc     = ValorDocumento
              , @vMarcaEntrada = HoraEntrada
              , @vMarcaSalida  = HoraSalida
            FROM @tMarcas
            WHERE (Fila = @vMarcaFila);

            EXEC dbo.sp_ProcesarAsistencia
                @inValorDocumento     = @vMarcaDoc
              , @inFechaHoraEntrada   = @vMarcaEntrada
              , @inFechaHoraSalida    = @vMarcaSalida
              , @inIdUsuarioSistema   = @inIdUsuarioSistema
              , @inIPOrigen           = @inIPOrigen
              , @outResultCode        = @vResultCode OUTPUT;

            SET @vMarcaFila = @vMarcaFila + 1;

        END;

        --Si es jueves: asignar jornadas de la siguiente semana

        IF (@vEsJueves = 1)
        BEGIN

            SET @vFechaViernes = DATEADD(DAY, 1, @vFechaActual);

            DECLARE @tJornadas TABLE (
                Fila            INT IDENTITY(1, 1)
              , ValorDocumento  VARCHAR(30)
              , NombreJornada   VARCHAR(50)
            );

            INSERT INTO @tJornadas (
                ValorDocumento
              , NombreJornada
            )
            SELECT
                n.value('@ValorDocumentoIdentidad', 'VARCHAR(30)')
              , n.value('@Jornada',                  'VARCHAR(50)')
            FROM @vNodoActual.nodes('/FechaOperacion/AsignarJornada') AS x(n);

            DECLARE @vJorFila        INT = 1;
            DECLARE @vJorTotal       INT;
            DECLARE @vJorDoc         VARCHAR(30);
            DECLARE @vJorNombre      VARCHAR(50);
            DECLARE @vJorIdTipo      INT;
            DECLARE @vJorIdEmpleado  INT;

            SELECT @vJorTotal = COUNT(*) FROM @tJornadas;

            WHILE (@vJorFila <= @vJorTotal)
            BEGIN

                SELECT
                    @vJorDoc    = ValorDocumento
                  , @vJorNombre = NombreJornada
                FROM @tJornadas
                WHERE (Fila = @vJorFila);

                SELECT @vJorIdTipo = tj.IdTipoJornada
                FROM dbo.TipoJornada AS tj
                WHERE (tj.Nombre = @vJorNombre);

                SELECT @vJorIdEmpleado = e.IdEmpleado
                FROM dbo.Empleado AS e
                WHERE (e.ValorDocumentoIdentidad = @vJorDoc);

                IF (@vJorIdTipo IS NOT NULL) AND (@vJorIdEmpleado IS NOT NULL)
                BEGIN
                    IF EXISTS (
                        SELECT 1
                        FROM dbo.JornadaEmpleadoSemana AS jes
                        WHERE (jes.IdEmpleado = @vJorIdEmpleado)
                          AND (jes.FechaInicioSemana = @vFechaViernes)
                    )
                        UPDATE dbo.JornadaEmpleadoSemana
                        SET IdTipoJornada = @vJorIdTipo
                        WHERE (IdEmpleado = @vJorIdEmpleado)
                          AND (FechaInicioSemana = @vFechaViernes);
                    ELSE
                        INSERT INTO dbo.JornadaEmpleadoSemana (
                            IdEmpleado
                          , IdTipoJornada
                          , FechaInicioSemana
                        )
                        VALUES (
                            @vJorIdEmpleado
                          , @vJorIdTipo
                          , @vFechaViernes
                        );
                END;

                SET @vJorFila = @vJorFila + 1;

            END;

            --Cierre semanal

            EXEC dbo.sp_CierreSemanal
                @inFechaJueves      = @vFechaActual
              , @inIdUsuarioSistema = @inIdUsuarioSistema
              , @inIPOrigen         = @inIPOrigen
              , @outResultCode      = @vResultCode OUTPUT;

            --Si el viernes siguiente es el primer viernes del mes: apertura de mes 

            SET @vEsUltimoJue = CASE
                WHEN (MONTH(@vFechaViernes) <> MONTH(@vFechaActual)) THEN 1
                ELSE 0
            END;

            IF (@vEsUltimoJue = 1)
            BEGIN

                SET @vFechaFinMesSig = dbo.fn_UltimoJuevesDelMes(YEAR(@vFechaViernes), MONTH(@vFechaViernes));
                SET @vNumJuevesSig   = dbo.fn_ContarJueves(@vFechaViernes, @vFechaFinMesSig);

                EXEC dbo.sp_AperturaMes
                    @inFechaInicioMes  = @vFechaViernes
                  , @inFechaFinMes     = @vFechaFinMesSig
                  , @inCantidadJueves  = @vNumJuevesSig
                  , @outResultCode     = @vResultCode OUTPUT;

            END;

            --Apertura de la siguiente semana 

            EXEC dbo.sp_AperturaSemana
                @inFechaInicioSemana = @vFechaViernes
              , @inFechaFinSemana    = DATEADD(DAY, 6, @vFechaViernes)
              , @outResultCode       = @vResultCode OUTPUT;

        END;

        SET @vFilaActual = @vFilaActual + 1;

        --Limpiar tablas variables de esta iteracion
        DELETE FROM @tNuevosEmpleados;
        DELETE FROM @tEliminarEmpleados;
        DELETE FROM @tAsociarDeducciones;
        DELETE FROM @tDesasociarDeducciones;
        DELETE FROM @tMarcas;

    END;

    PRINT 'Simulacion completada exitosamente.';

END;
GO

PRINT 'SPs de simulacion creados exitosamente.';
GO