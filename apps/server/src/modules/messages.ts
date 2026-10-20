import { z } from "zod";
import { db } from "../services/db";
import { membership, sendMessage } from "../services/messages";
import { requireCondition } from "../security/errors";
import { uuid } from "../../../../packages/contracts";
export async function messagesRoute(
  userId: string,
  method: string,
  path: string[],
  body: unknown,
) {
  const [, id, sub] = path;
  const m = await db.message.findUnique({ where: { id: uuid.parse(id) } });
  requireCondition(m, 404, "NOT_FOUND");
  await membership(userId, m.conversationId);
  if (sub === "recall" && method === "POST") {
    requireCondition(
      m.senderId === userId && Date.now() - m.createdAt.getTime() < 120000,
      403,
      "RECALL_WINDOW_EXPIRED",
    );
    return db.$transaction(async (tx) => {
      const result = await tx.message.update({
        where: { id },
        data: { text: "", mediaId: null, recalledAt: new Date() },
      });
      const members = await tx.conversationMember.findMany({
        where: { conversationId: m.conversationId },
      });
      for (const member of members)
        await tx.outbox.create({
          data: {
            room: `user:${member.userId}`,
            event: "message:recall",
            payload: { id, conversationId: m.conversationId },
          },
        });
      return result;
    });
  }
  if (sub === "forward" && method === "POST") {
    requireCondition(!m.recalledAt, 400, "RECALLED");
    const v = z
      .object({ conversationId: uuid, clientId: uuid })
      .strict()
      .parse(body);
    return sendMessage(userId, {
      ...v, kind: m.kind as "TEXT", text: m.text,
      ...(m.mediaId ? { mediaId: m.mediaId } : {}),
    }, m.id);
  }
  if (!sub && method === "DELETE")
    return db.messageUserState.upsert({
      where: { messageId_userId: { messageId: id, userId } },
      create: { messageId: id, userId, hidden: true },
      update: { hidden: true },
    });
  if (sub === "favorite" && method === "PATCH") {
    const { favorite } = z
      .object({ favorite: z.boolean() })
      .strict()
      .parse(body);
    return db.messageUserState.upsert({
      where: { messageId_userId: { messageId: id, userId } },
      create: { messageId: id, userId, favorite },
      update: { favorite },
    });
  }
}
