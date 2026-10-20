import { Prisma } from "@prisma/client";
import { db } from "./db";
import { ApiError, requireCondition } from "../security/errors";
import {
  messageSchema,
  type MessageInput,
} from "../../../../packages/contracts";
export const publicUser = {
  id: true,
  qchatId: true,
  nickname: true,
  avatarId: true,
  bio: true,
} as const;
export async function membership(userId: string, conversationId: string) {
  const m = await db.conversationMember.findUnique({
    where: { conversationId_userId: { conversationId, userId } },
  });
  requireCondition(m);
  return m;
}
export async function unblocked(a: string, b: string) {
  requireCondition(
    !(await db.blockedUser.findFirst({
      where: {
        OR: [
          { ownerId: a, targetId: b },
          { ownerId: b, targetId: a },
        ],
      },
    })),
    403,
    "USER_BLOCKED",
  );
}
export async function sendMessage(userId: string, raw: MessageInput, forwardSourceId?: string) {
  const input = messageSchema.parse(raw);
  for (let attempt = 0; attempt < 4; attempt++)
    try {
      return await db.$transaction(
        async (tx) => {
          const member = await tx.conversationMember.findUnique({
            where: {
              conversationId_userId: {
                conversationId: input.conversationId,
                userId,
              },
            },
          });
          requireCondition(member);
          const prior = await tx.message.findUnique({
            where: {
              senderId_clientId: { senderId: userId, clientId: input.clientId },
            },
          });
          if (prior) {
            requireCondition(
              prior.conversationId === input.conversationId,
              409,
              "IDEMPOTENCY_CONFLICT",
            );
            return prior;
          }
          const c = await tx.conversation.findUniqueOrThrow({
            where: { id: input.conversationId },
            include: { members: true },
          });
          if (c.kind === "DIRECT") {
            const other = c.members.find((m) => m.userId !== userId);
            requireCondition(other);
            const blocked = await tx.blockedUser.findFirst({
              where: {
                OR: [
                  { ownerId: userId, targetId: other.userId },
                  { ownerId: other.userId, targetId: userId },
                ],
              },
            });
            requireCondition(!blocked, 403, "USER_BLOCKED");
          }
          if (input.replyToId)
            requireCondition(
              await tx.message.findFirst({
                where: { id: input.replyToId, conversationId: c.id },
              }),
              400,
              "INVALID_REPLY",
            );
          if (forwardSourceId) {
            const source = await tx.message.findFirst({
              where: { id: forwardSourceId, recalledAt: null, states: { none: { userId, hidden: true } } },
            });
            const sourceMember = source && await tx.conversationMember.findUnique({
              where: { conversationId_userId: { conversationId: source.conversationId, userId } },
            });
            requireCondition(source && sourceMember && source.sequence > sourceMember.clearedSequence &&
              source.mediaId === (input.mediaId ?? null), 403, "FORWARD_SOURCE_UNAVAILABLE");
          }
          if (input.mediaId)
            requireCondition(
              await tx.media.findFirst({
                where: { id: input.mediaId, ...(forwardSourceId ? {} : { ownerId: userId }), status: "READY" },
              }),
              400,
              "MEDIA_NOT_READY",
            );
          const updated = await tx.conversation.update({
            where: { id: c.id },
            data: { sequence: { increment: 1 } },
          });
          const message = await tx.message.create({
            data: { ...input, senderId: userId, sequence: updated.sequence },
          });
          await tx.conversationMember.updateMany({
            where: { conversationId: c.id },
            data: { hidden: false },
          });
          for (const recipient of c.members)
            await tx.outbox.create({
              data: {
                event: "message:new",
                room: `user:${recipient.userId}`,
                payload: JSON.parse(JSON.stringify(message)),
              },
            });
          return message;
        },
        { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
      );
    } catch (error) {
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        ["P2034", "P2002"].includes(error.code) &&
        attempt < 3
      )
        continue;
      throw error;
    }
  throw new ApiError(409, "RETRY_REQUIRED");
}
export async function receipt(
  userId: string,
  conversationId: string,
  sequence: number,
  read: boolean,
) {
  await membership(userId, conversationId);
  const c = await db.conversation.findUniqueOrThrow({
    where: { id: conversationId },
  });
  requireCondition(sequence <= c.sequence, 400, "INVALID_SEQUENCE");
  const field = read ? "readSequence" : "deliveredSequence";
  await db.$transaction(async (tx) => {
    if (read) await tx.conversationMember.updateMany({
      where: { conversationId, userId },
      data: { markedUnread: false },
    });
    const changed = await tx.conversationMember.updateMany({
      where: { conversationId, userId, [field]: { lt: sequence } },
      data: { [field]: sequence },
    });
    if (read) await tx.conversationMember.updateMany({
      where: { conversationId, userId, deliveredSequence: { lt: sequence } },
      data: { deliveredSequence: sequence },
    });
    if (changed.count) {
      const members = await tx.conversationMember.findMany({where:{conversationId}});
      await tx.outbox.createMany({data:members.map(member => ({
        event: read ? 'message:read' : 'message:delivered',
        room: `user:${member.userId}`,
        payload: {conversationId,userId,sequence},
      }))});
    }
  });
  return { conversationId, userId, sequence };
}
