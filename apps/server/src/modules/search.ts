import { z } from "zod";
import { db } from "../services/db";
import { publicUser } from "../services/messages";

export async function searchRoute(userId: string, url: URL) {
  const q = z.string().trim().min(1).max(100).parse(url.searchParams.get("q"));
  const contains = { contains: q, mode: "insensitive" as const };
  const memberships = await db.conversationMember.findMany({
    where: { userId, hidden: false },
    select: { conversationId: true, clearedSequence: true },
  });
  const [friends, conversations, messages] = await Promise.all([
    db.friendship.findMany({
      where: {
        ownerId: userId,
        OR: [{ remark: contains }, { friend: { nickname: contains } },
          { friend: { qchatId: contains } }],
      },
      include: { friend: { select: publicUser } },
      take: 30,
    }),
    db.conversation.findMany({
      where: {
        members: { some: { userId, hidden: false } },
        OR: [{ title: contains }, { members: { some: {
          userId: { not: userId }, user: { nickname: contains },
        } } }],
      },
      include: { members: { include: { user: { select: publicUser } } } },
      orderBy: { updatedAt: "desc" }, take: 30,
    }),
    db.message.findMany({
      where: {
        text: contains,
        recalledAt: null,
        OR: memberships.map(m => ({
          conversationId: m.conversationId, sequence: { gt: m.clearedSequence },
        })),
        conversation: { members: { some: { userId, hidden: false } } },
        states: { none: { userId, hidden: true } },
      },
      include: { sender: { select: publicUser } },
      orderBy: { createdAt: "desc" }, take: 50,
    }),
  ]);
  return { friends, conversations, messages };
}
