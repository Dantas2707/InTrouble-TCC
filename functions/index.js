const admin = require("firebase-admin");
const {
  onDocumentCreated,
  onDocumentUpdated,
} = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");
const nodemailer = require("nodemailer");

admin.initializeApp();

// ================== VARIÁVEIS DE AMBIENTE ==================
const gmailUser = process.env.GMAIL_USER || "";
const gmailPass = process.env.GMAIL_PASS || "";

if (!gmailUser || !gmailPass) {
  // Aviso apenas (no deploy o .env pode não estar carregado ainda)
  logger.warn(
    "GMAIL_USER ou GMAIL_PASS não configurados nas variáveis de ambiente (serão lidos em runtime se existirem)."
  );
}

// ================== NODEMAILER ==================
const transporter = nodemailer.createTransport({
  host: "smtp.gmail.com",
  port: 465,
  secure: true,
  auth: {
    user: gmailUser,
    pass: gmailPass,
  },
});

// ---------------- HELPERS ----------------

async function buscarUsuario(uid) {
  if (!uid) return null;
  const snap = await admin.firestore().collection("usuario").doc(uid).get();
  return snap.exists ? snap.data() : null;
}

async function buscarEmailsGuardioes(guardioesIds) {
  if (!Array.isArray(guardioesIds) || guardioesIds.length === 0) return [];

  const emails = [];

  for (const guardiaoId of guardioesIds) {
    try {
      const dados = await buscarUsuario(guardiaoId);
      const email =
        (dados && dados.email && dados.email.toString().trim()) || "";
      if (email) {
        emails.push(email);
      } else {
        logger.warn(`[SOS] Guardião ${guardiaoId} sem e-mail cadastrado`);
      }
    } catch (e) {
      logger.error(`[SOS] Erro ao buscar guardião ${guardiaoId}`, e);
    }
  }

  return emails;
}

async function enviarEmailParaGuardioes({
  assunto,
  texto,
  destinatarios,
  html,
}) {
  if (!destinatarios || destinatarios.length === 0) {
    logger.warn("[SOS] Nenhum destinatário para enviar e-mail.");
    return;
  }

  const mailOptions = {
    from: `"InTrouble" <${gmailUser}>`,
    to: destinatarios.join(","),
    subject: assunto,
    text: texto,
  };

  if (html) {
    mailOptions.html = html;
  }

  await transporter.sendMail(mailOptions);
}

// ================== FUNÇÃO: SOS CRIADO ==================

exports.onSosCreated = onDocumentCreated(
  "ocorrencias/{ocorrenciaId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const ocorrencia = snap.data();
    const ocorrenciaId = event.params.ocorrenciaId;

    // Só queremos ocorrências SOS
    if (!ocorrencia || (!ocorrencia.isSos && ocorrencia.tipoOcorrencia !== "SOS")) {
      return;
    }

    logger.info("[SOS] Nova ocorrência SOS criada", { ocorrenciaId, ocorrencia });

    const ownerUid = ocorrencia.ownerUid;

    // Pega tanto idGuardiao (camelCase) quanto id_guardiao (snake_case)
    const guardioesIds = ocorrencia.idGuardiao || ocorrencia.id_guardiao || [];

    // Dados da vítima
    let nomeVitima = "Usuário";
    try {
      const dadosVitima = await buscarUsuario(ownerUid);
      if (dadosVitima && dadosVitima.nome) {
        nomeVitima = dadosVitima.nome;
      }
    } catch (e) {
      logger.error("[SOS] Erro ao buscar dados da vítima", e);
    }

    // E-mails dos guardiões
    const emailsGuardioes = await buscarEmailsGuardioes(guardioesIds);
    if (emailsGuardioes.length === 0) {
      logger.warn(
        "[SOS] Nenhum e-mail de guardião encontrado para esta ocorrência."
      );
      return;
    }

    const gravidade = ocorrencia.nivelgravidade || "Gravíssima";

    // -------- Localização (frase fixa, sem mapa) --------
    const textoLocalizacao =
      'Localização da vítima pode ser visualizada na tela "Localização da vítima" do aplicativo InTrouble.';

    const htmlLocalizacao = `
      <p><strong>Localização da vítima</strong></p>
      <p>
        A localização da vítima pode ser visualizada na tela
        <strong>"Localização da vítima"</strong> do aplicativo
        <strong>InTrouble</strong>.
      </p>
    `;

    const assunto = `⚠️ SOS InTrouble - ${nomeVitima} acionou o botão de emergência`;

    // Corpo em TEXTO (fallback)
    const texto = `Olá, guardião(ã).

${nomeVitima} acionou o SOS no aplicativo InTrouble.

Detalhes da ocorrência:
- Gravidade informada: ${gravidade}
- Situação: EM ANDAMENTO

${textoLocalizacao}

Acesse o aplicativo InTrouble para acompanhar a ocorrência em tempo real,
visualizar a localização da vítima e registrar observações, se necessário.

— Equipe InTrouble`;

    // Corpo em HTML
    const html = `<!DOCTYPE html>
<html lang="pt-BR">
  <body style="margin:0;padding:0;background:#f4f4f5;font-family:Arial,Helvetica,sans-serif;">
    <div style="max-width:600px;margin:0 auto;padding:24px;background:#ffffff;">
      <h2 style="margin-top:0;color:#111827;">⚠️ SOS InTrouble</h2>

      <p>Olá, guardião(ã).</p>

      <p>
        <strong>${nomeVitima}</strong> acionou o SOS no aplicativo
        <strong>InTrouble</strong>.
      </p>

      <p><strong>Detalhes da ocorrência:</strong></p>
      <ul>
        <li>Gravidade informada: <strong>${gravidade}</strong></li>
        <li>Situação: <strong>EM ANDAMENTO</strong></li>
      </ul>

      ${htmlLocalizacao}

      <p style="margin-top:24px;">
        Acesse o aplicativo <strong>InTrouble</strong> para acompanhar a ocorrência
        em tempo real, visualizar a localização da vítima e registrar
        observações, se necessário.
      </p>

      <p style="margin-top:32px;">— Equipe InTrouble</p>
    </div>
  </body>
</html>`;

    try {
      await enviarEmailParaGuardioes({
        assunto,
        texto,
        html,
        destinatarios: emailsGuardioes,
      });
      logger.info("[SOS] E-mails de SOS enviados com sucesso", {
        ocorrenciaId,
        emails: emailsGuardioes,
      });
    } catch (e) {
      logger.error("[SOS] Erro ao enviar e-mails de SOS", e);
    }
  }
);

// ================== FUNÇÃO: SOS FINALIZADO ==================

exports.onSosFinalizado = onDocumentUpdated(
  "ocorrencias/{ocorrenciaId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    const ocorrenciaId = event.params.ocorrenciaId;

    if (!after || (!after.isSos && after.tipoOcorrencia !== "SOS")) {
      return;
    }

    // Só quando muda de aberto -> finalizado
    if (before?.status === "aberto" && after.status === "finalizado") {
      logger.info("[SOS] Ocorrência SOS finalizada, enviando e-mails", {
        ocorrenciaId,
        after,
      });

      const ownerUid = after.ownerUid;
      const guardioesIds = after.idGuardiao || after.id_guardiao || [];

      let nomeVitima = "Usuário";
      try {
        const dadosVitima = await buscarUsuario(ownerUid);
        if (dadosVitima && dadosVitima.nome) {
          nomeVitima = dadosVitima.nome;
        }
      } catch (e) {
        logger.error("[SOS] Erro ao buscar dados da vítima (finalização)", e);
      }

      const emailsGuardioes = await buscarEmailsGuardioes(guardioesIds);
      if (emailsGuardioes.length === 0) {
        logger.warn(
          "[SOS] Nenhum e-mail de guardião encontrado (finalização)."
        );
        return;
      }

      const assunto = `✅ InTrouble - SOS finalizado para ${nomeVitima}`;

      const texto = `Olá, guardião(ã).

A ocorrência de SOS de ${nomeVitima} foi marcada como FINALIZADA no aplicativo InTrouble.

Resumo:
- Status atual: finalizado
- ID da ocorrência: ${ocorrenciaId}

Se ainda houver qualquer sinal de risco, entre em contato com a vítima
e, se necessário, acione os serviços de emergência da sua região.

— Equipe InTrouble`;

      const html = `<!DOCTYPE html>
<html lang="pt-BR">
  <body style="margin:0;padding:0;background:#f4f4f5;font-family:Arial,Helvetica,sans-serif;">
    <div style="max-width:600px;margin:0 auto;padding:24px;background:#ffffff;">
      <h2 style="margin-top:0;color:#16a34a;">✅ InTrouble - SOS finalizado</h2>

      <p>Olá, guardião(ã).</p>

      <p>
        A ocorrência de SOS de <strong>${nomeVitima}</strong> foi marcada como
        <strong>FINALIZADA</strong> no aplicativo InTrouble.
      </p>

      <p><strong>Resumo:</strong></p>
      <ul>
        <li>Status atual: <strong>finalizado</strong></li>
        <li>ID da ocorrência: <code>${ocorrenciaId}</code></li>
      </ul>

      <p style="margin-top:24px;">
        Se ainda houver qualquer sinal de risco, entre em contato com a vítima e,
        se necessário, acione os serviços de emergência da sua região.
      </p>

      <p style="margin-top:32px;">— Equipe InTrouble</p>
    </div>
  </body>
</html>`;

      try {
        await enviarEmailParaGuardioes({
          assunto,
          texto,
          html,
          destinatarios: emailsGuardioes,
        });
        logger.info("[SOS] E-mails de finalização enviados com sucesso", {
          ocorrenciaId,
          emails: emailsGuardioes,
        });
      } catch (e) {
        logger.error(
          "[SOS] Erro ao enviar e-mails de finalização de SOS",
          e
        );
      }
    }
  }
);
