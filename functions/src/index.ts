// import * as functions from 'firebase-functions';
// import * as admin from 'firebase-admin';

// admin.initializeApp();

// // Função que envia a notificação de SOS para o guardião
// export const sendSOSNotification = functions.firestore
//     .document('ocorrencias/{ocorrenciaId}')  // A nova sintaxe da versão 2
//     .onCreate(async (snap) => {
//         const doc = snap.data();  // Acessa os dados do documento após a criação

//         if (!doc) {
//             console.log('Documento não encontrado');
//             return null;
//         }

//         const ocorrenciaData = doc;
//         const userId = ocorrenciaData?.userId; // id do guardião
        
//         const token = await getGuardiaoToken(userId);

//         if (!token) {
//             console.log('Token do guardião não encontrado');
//             return null;
//         }

//         const message = {
//             notification: {
//                 title: 'Alerta de SOS!',
//                 body: 'Uma vítima acionou o botão SOS.',
//             },
//             android: {
//                 notification: {
//                     sound: 'default',  // Som padrão de notificação no Android
//                 },
//             },
//             token: token,
//         };

//         try {
//             const response = await admin.messaging().send(message);
//             console.log('Notificação enviada com sucesso:', response);
//             return null;
//         } catch (error) {
//             console.error('Erro ao enviar notificação:', error);
//             return null;
//         }
//     });

// // Função para buscar o token do guardião
// async function getGuardiaoToken(userId: string): Promise<string | null> {
//     const userRef = admin.firestore().collection('users').doc(userId);
//     const doc = await userRef.get();

//     if (!doc.exists) {
//         console.log('Usuário não encontrado');
//         return null;
//     }

//     const userData = doc.data();
//     return userData?.fcmToken || null;
// }
